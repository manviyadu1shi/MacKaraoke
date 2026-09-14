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
        case .sung, .active: return .white.opacity(0.95)
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
}//
//  KaraokeView.swift
//  MacKaraoke
//
//  Created by Manvi Yaduvanshi on 14/09/26.
//

