import Foundation

protocol LyricsProvider {
    func fetchLyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics?
}

// LRCLIB (lrclib.net) — free, public, no API key, community-maintained
// synced lyrics database. Line-level timestamps only; we interpolate
// approximate word timings within each line's span (see LyricLine
// extension below) so the karaoke engine still has something to
// animate against.
final class LRCLIBProvider: LyricsProvider {
    func fetchLyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = json["syncedLyrics"] as? String, !synced.isEmpty else {
                return nil
            }
            return parse(lrc: synced)
        } catch {
            print("LRCLIB fetch failed: \(error)")
            return nil
        }
    }

    private func parse(lrc: String) -> Lyrics? {
        let pattern = #"^\[(\d+):(\d+(?:\.\d+)?)\](.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var raw: [(time: TimeInterval, text: String)] = []
        for rawLine in lrc.components(separatedBy: "\n") {
            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            guard let match = regex.firstMatch(in: rawLine, range: range),
                  let minutesRange = Range(match.range(at: 1), in: rawLine),
                  let secondsRange = Range(match.range(at: 2), in: rawLine),
                  let textRange = Range(match.range(at: 3), in: rawLine),
                  let minutes = Double(rawLine[minutesRange]),
                  let seconds = Double(rawLine[secondsRange]) else { continue }

            let text = rawLine[textRange].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            raw.append((minutes * 60 + seconds, text))
        }

        guard !raw.isEmpty else { return nil }
        raw.sort { $0.time < $1.time }

        var lines: [LyricLine] = []
        for (index, entry) in raw.enumerated() {
            let end = index + 1 < raw.count ? raw[index + 1].time : entry.time + 4.0
            lines.append(.interpolated(text: entry.text, start: entry.time, end: end))
        }
        return Lyrics(lines: lines)
    }
}//
//  LyricsProvider.swift
//  MacKaraoke
//
//  Created by Manvi Yaduvanshi on 14/09/26.
//

