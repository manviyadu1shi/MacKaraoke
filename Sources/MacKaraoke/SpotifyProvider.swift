import Foundation
import AppKit

final class SpotifyProvider: MediaProvider {
    var onUpdate: ((NowPlayingInfo?) -> Void)?
    private var driftTimer: Timer?

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNotification),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )

        // Slow drift-correction poll only — not per-frame.
        driftTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshFromAppleScript()
        }

        refreshFromAppleScript()
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        driftTimer?.invalidate()
        driftTimer = nil
    }

    @objc private func handleNotification(_ note: Notification) {
        refreshFromAppleScript()
    }

    private func refreshFromAppleScript() {
        guard isSpotifyRunning() else {
            onUpdate?(nil)
            return
        }

        let script = """
        tell application "Spotify"
            if player state is stopped then
                return "STOPPED"
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to (duration of current track) / 1000
            set trackPosition to player position
            set isPlaying to (player state is playing)
            return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & trackDuration & "||" & trackPosition & "||" & isPlaying
        end tell
        """

        guard let scriptObject = NSAppleScript(source: script) else {
            onUpdate?(nil)
            return
        }

        var error: NSDictionary?
        let result = scriptObject.executeAndReturnError(&error)

        if let error {
            // Most commonly: Automation permission not yet granted.
            print("AppleScript error talking to Spotify: \(error)")
            onUpdate?(nil)
            return
        }

        guard let raw = result.stringValue, raw != "STOPPED" else {
            onUpdate?(nil)
            return
        }

        let parts = raw.components(separatedBy: "||")
        guard parts.count == 6,
              let duration = Double(parts[3]),
              let position = Double(parts[4]) else {
            onUpdate?(nil)
            return
        }

        onUpdate?(NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[5] == "true",
            position: position,
            duration: duration
        ))
    }

    private func isSpotifyRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }
}
