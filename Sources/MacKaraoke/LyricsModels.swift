import Foundation

struct LyricWord {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct LyricLine {
    let words: [LyricWord]
    var start: TimeInterval { words.first?.start ?? 0 }
    var end: TimeInterval { words.last?.end ?? 0 }
}

struct Lyrics {
    let lines: [LyricLine]
    var totalDuration: TimeInterval { lines.last?.end ?? 0 }
}

extension LyricLine {
    // Builds a line from raw LRC text + its known start/end time by
    // evenly splitting the words across that span — an approximation,
    // since LRCLIB only gives us line-level timing.
    static func interpolated(text: String, start: TimeInterval, end: TimeInterval) -> LyricLine {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return LyricLine(words: [LyricWord(text: "♪", start: start, end: end)])
        }
        let span = max(end - start, 0.1)
        let perWord = span / Double(tokens.count)
        let words = tokens.enumerated().map { idx, token in
            LyricWord(text: token, start: start + Double(idx) * perWord, end: start + Double(idx + 1) * perWord)
        }
        return LyricLine(words: words)
    }
}//
//  LyricsModels.swift
//  MacKaraoke
//
//  Created by Manvi Yaduvanshi on 14/09/26.
//

