import AppKit
import SwiftUI

// PHASE 1 GOAL (carried forward): reliably place custom UI in the screen
// space to the left and right of the physical notch without covering it
// or interfering with the real menu bar.
//
// PHASE 2 ADDS: a fake local playback clock + word-level lyrics sync,
// rendered via KaraokeOverlayView (see KaraokeView.swift). Still no
// Spotify — the clock just counts up on its own.
//
// This revision also adds hover-to-fade: moving the mouse into the menu
// bar strip fades the overlay out so it never blocks real menu bar clicks.

// MARK: - Overlay window

// A borderless, transparent, click-through window sized to exactly one
// notch-adjacent region. We make one instance for the left area and one
// for the right area rather than a single window spanning the notch —
// this way nothing is ever drawn under the notch, by construction.
final class OverlayWindow: NSWindow {
    init<Content: View>(rect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Transparent, chrome-less, no shadow — this should read as "not
        // a normal app window" at all.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true       // click-through: never intercepts input
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // Sit above normal app windows, in the menu-bar layer.
        // NOTE: this is the single most likely thing to need tuning once
        // you actually see it against the real menu bar.
        level = .statusBar

        contentView = NSHostingView(rootView: content())
        orderFrontRegardless()
    }
}

// MARK: - Notch geometry

enum NotchGeometry {
    /// Returns (leftRect, rightRect) in screen coordinates for the usable
    /// space flanking the notch, or nil if this screen has no notch.
    static func auxiliaryAreas(for screen: NSScreen) -> (left: NSRect, right: NSRect)? {
        guard screen.safeAreaInsets.top > 0 else {
            // No notch on this display (e.g. external monitor, older MacBook).
            return nil
        }

        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }

        return (left, right)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindows: [OverlayWindow] = []
    private var statusItem: NSStatusItem?
    private let clock = PlaybackClock()
    private let lyricsStore = LyricsStore()
    private let spotifyProvider = SpotifyProvider()
    private let lyricsProvider = LRCLIBProvider()
    private var lastFetchedKey: String?

    // Hover-to-fade state
    private var mouseMonitor: Any?
    private var isHoveringMenuBar = false
    private var menuBarHitRect: NSRect = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no app switcher entry — this should feel invisible.
        NSApp.setActivationPolicy(.accessory)
        spotifyProvider.onUpdate = { [weak self] info in
            guard let self else { return }
            guard let info else {
                self.clock.pause()
                Task { @MainActor in
                    self.lyricsStore.lyrics = nil
                    self.lyricsStore.statusText = "Waiting for Spotify"
                }
                return
            }
            self.clock.sync(to: info.position, isPlaying: info.isPlaying)

            let key = "\(info.title)|\(info.artist)"
            if key != self.lastFetchedKey {
                self.lastFetchedKey = key
                self.lyricsStore.lyrics = nil
                self.lyricsStore.statusText = "Finding lyrics"

                Task {
                    let lyrics = await self.lyricsProvider.fetchLyrics(
                        title: info.title, artist: info.artist, album: info.album, duration: info.duration
                    )
                    await MainActor.run {
                        guard self.lastFetchedKey == key else { return }
                        self.lyricsStore.lyrics = lyrics
                        self.lyricsStore.statusText = lyrics == nil ? "No synced lyrics" : ""
                    }

                    if let lyrics {
                        print("Fetched \(lyrics.lines.count) synced lines for \(info.title).")
                    } else {
                        print("No synced lyrics found for \(info.title) — \(info.artist).")
                    }
                }
            }
        }
        spotifyProvider.start()

        setUpOverlays()
        setUpStatusItem()
    }

    private func setUpOverlays() {
        guard let screen = NSScreen.main else {
            print("No main screen found.")
            return
        }

        guard let areas = NotchGeometry.auxiliaryAreas(for: screen) else {
            print("This screen doesn't report a notch (safeAreaInsets.top == 0).")
            print("Auxiliary-area windows were not created. See README for the fallback plan.")
            return
        }

        print("Notch detected.")
        print("Left auxiliary area:  \(areas.left)")
        print("Right auxiliary area: \(areas.right)")

        // The auxiliary area macOS reports is flush against the physical
        // top of the screen with no slack. Rather than offsetting the
        // rendered text (which just gets clipped by the window bounds),
        // we grow the window's height downward so the padded text has
        // real room to sit in. The top edge stays anchored at the screen
        // edge; only the bottom edge extends further down the screen.
        let verticalSlack: CGFloat = 8

        let leftRect = NSRect(
            x: areas.left.origin.x,
            y: areas.left.origin.y - verticalSlack,
            width: areas.left.width,
            height: areas.left.height + verticalSlack
        )
        let rightRect = NSRect(
            x: areas.right.origin.x,
            y: areas.right.origin.y - verticalSlack,
            width: areas.right.width,
            height: areas.right.height + verticalSlack
        )

        let leftWindow = OverlayWindow(rect: leftRect) {
            KaraokeOverlayView(clock: clock, lyricsStore: lyricsStore, alignment: .trailing, showNextLine: false)
        }
        let rightWindow = OverlayWindow(rect: rightRect) {
            KaraokeOverlayView(clock: clock, lyricsStore: lyricsStore, alignment: .leading, showNextLine: true)
        }

        overlayWindows = [leftWindow, rightWindow]

        // Hover zone spans the full screen width at the same height as the
        // overlay windows, so moving toward any part of the menu bar (not
        // just directly over our text) triggers the fade.
//        let hitRect = NSRect(
//            x: screen.frame.minX,
//            y: leftRect.origin.y,
//            width: screen.frame.width,
//            height: leftRect.height
//        )
        // Use the real system menu bar height (screen frame minus visible frame),
        // not our smaller overlay rect — this guarantees the hover zone covers
        // the entire menu bar strip, including areas we don't draw text in.
        let menuBarHeight = screen.frame.height - screen.visibleFrame.height
        let hitRect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        setUpHoverDetection(hitRect: hitRect)

//        clock.play()
    }

    // A small real menu-bar item is added purely so you have a way to quit
    // the app during testing (accessory apps have no Dock icon, so Cmd+Q
    // has no obvious target otherwise). This lives in the normal menu bar
    // area, not inside the notch-adjacent overlay windows.
    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MacKaraoke")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Play", action: #selector(playClock), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Pause", action: #selector(pauseClock), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Restart", action: #selector(restartClock), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MacKaraoke", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    @objc private func playClock() { clock.play() }
    @objc private func pauseClock() { clock.pause() }
    @objc private func restartClock() { clock.restart() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hover-to-fade

    private func setUpHoverDetection(hitRect: NSRect) {
        menuBarHitRect = hitRect
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.checkHover()
        }
    }

    private func checkHover() {
        let hovering = menuBarHitRect.contains(NSEvent.mouseLocation)
        guard hovering != isHoveringMenuBar else { return }
        isHoveringMenuBar = hovering

        for window in overlayWindows {
            if hovering {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.15
                    window.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    // Only actually hide if we're still supposed to be hidden —
                    // the cursor may have already left the menu bar again by
                    // the time this fires.
                    guard let self, self.isHoveringMenuBar else { return }
                    window.orderOut(nil)
                })
            } else {
                window.alphaValue = 0
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    window.animator().alphaValue = 1
                }
            }
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
