import SwiftUI

enum WordState {
    case sung, active, upcoming
}

struct KaraokeLineView: View {
    let line: LyricLine
    let currentTime: TimeInterval
    let alignment: Alignment
    let dimmed: Bool // true for the "upcoming line" preview on the right

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                Text(word.text)
                    .font(.system(size: 13, weight: state(for: word) == .sung ? .semibold : .medium))
                    .foregroundColor(color(for: word))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func state(for word: LyricWord) -> WordState {
        if currentTime >= word.end { return .sung }
        if currentTime >= word.start { return .active }
        return .upcoming
    }

    private func color(for word: LyricWord) -> Color {
        if dimmed { return .white.opacity(0.35) }
        switch state(for: word) {
        case .sung, .active: return Color(hex: "#1db954")
        case .upcoming: return .white.opacity(0.4)
        }
    }
}

final class LyricsStore: ObservableObject {
    @Published var lyrics: Lyrics?
    @Published var statusText = "Waiting for Spotify"
}

struct KaraokeOverlayView: View {
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var lyricsStore: LyricsStore
    let alignment: Alignment
    let showNextLine: Bool // false = current line, true = upcoming line preview

    var body: some View {
        if let lyrics = lyricsStore.lyrics, !lyrics.lines.isEmpty {
            let t = clock.currentTime.truncatingRemainder(dividingBy: max(lyrics.totalDuration, 0.01))
            let currentIndex = lyrics.lines.firstIndex(where: { t < $0.end }) ?? lyrics.lines.count - 1

            if showNextLine {
                let nextIndex = min(currentIndex + 1, lyrics.lines.count - 1)
                KaraokeLineView(line: lyrics.lines[nextIndex], currentTime: t, alignment: alignment, dimmed: true)
            } else {
                KaraokeLineView(line: lyrics.lines[currentIndex], currentTime: t, alignment: alignment, dimmed: false)
            }
        } else {
            Text(lyricsStore.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(showNextLine ? 0.35 : 0.75))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 8)
                .padding(.top, 8)
        }
    }
}

enum NotchKaraokeSide {
    case left, right
}

struct NotchKaraokeContainerView: View {
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var lyricsStore: LyricsStore
    let side: NotchKaraokeSide

    var body: some View {
        HStack(spacing: 8) {
            if side == .left {
                WaveformView(clock: clock)
                    .frame(width: 58, height: 18)

                CompactLyricsView(
                    clock: clock,
                    lyricsStore: lyricsStore,
                    alignment: .trailing,
                    showNextLine: false
                )
            } else {
                CompactLyricsView(
                    clock: clock,
                    lyricsStore: lyricsStore,
                    alignment: .leading,
                    showNextLine: true
                )

                AlbumArtworkPlaceholderView()
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}


private struct CompactLyricsView: View {
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var lyricsStore: LyricsStore
    let alignment: Alignment
    let showNextLine: Bool

    var body: some View {
        Group {
            if let lyrics = lyricsStore.lyrics, !lyrics.lines.isEmpty {
                let t = clock.currentTime.truncatingRemainder(dividingBy: max(lyrics.totalDuration, 0.01))
                let currentIndex = lyrics.lines.firstIndex(where: { t < $0.end }) ?? lyrics.lines.count - 1
                let lineIndex = showNextLine ? min(currentIndex + 1, lyrics.lines.count - 1) : currentIndex

                CompactKaraokeLineView(
                    line: lyrics.lines[lineIndex],
                    currentTime: t,
                    alignment: alignment,
                    dimmed: showNextLine
                )
            } else {
                Text(lyricsStore.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(showNextLine ? 0.35 : 0.72))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }
}

private struct CompactKaraokeLineView: View {
    let line: LyricLine
    let currentTime: TimeInterval
    let alignment: Alignment
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                Text(word.text)
                    .font(.system(size: 13, weight: state(for: word) == .sung ? .semibold : .medium))
                    .foregroundColor(color(for: word))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .clipped()
    }

    private func state(for word: LyricWord) -> WordState {
        if currentTime >= word.end { return .sung }
        if currentTime >= word.start { return .active }
        return .upcoming
    }

    private func color(for word: LyricWord) -> Color {
        if dimmed { return .white.opacity(0.35) }

        switch state(for: word) {
        case .sung, .active: return Color(hex: "#1db954").opacity(0.96)
        case .upcoming: return .white.opacity(0.38)
        }
    }
}

private struct WaveformView: View {
    @ObservedObject var clock: PlaybackClock

    private let barCount = 12

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 3) ? Color.green.opacity(0.9) : Color.white.opacity(0.78))
                    .frame(width: 3, height: barHeight(at: index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: clock.currentTime)
        .animation(.easeInOut(duration: 0.2), value: clock.isPlaying)
    }

    private func barHeight(at index: Int) -> CGFloat {
        guard clock.isPlaying else { return CGFloat(4 + (index % 3) * 2) }

        let time = clock.currentTime
        let phase = Double(index) * 0.72
        let primary = (sin(time * 5.2 + phase) + 1) / 2
        let secondary = (sin(time * 8.1 + phase * 0.6) + 1) / 2
        let mixed = (primary * 0.65) + (secondary * 0.35)
        return CGFloat(5 + mixed * 17)
    }
}

private struct AlbumArtworkPlaceholderView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.12))

            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}//
//  KaraokeView.swift
//  MacKaraoke
//
//  Created by Manvi Yaduvanshi on 14/09/26.
//

