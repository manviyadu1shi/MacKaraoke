import Foundation
import Combine

// Stands in for the real media-driven clock that arrives in Phase 3.
// Same play/pause/seek interface — only the driving source changes later.
final class PlaybackClock: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false

    private var timer: Timer?
    private var startDate: Date?

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        startDate = Date().addingTimeInterval(-currentTime)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        seek(to: 0)
        if !isPlaying { play() }
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        if isPlaying { startDate = Date().addingTimeInterval(-time) }
    }

    private func tick() {
        guard let start = startDate else { return }
        currentTime = Date().timeIntervalSince(start)
    }
    
    func sync(to time: TimeInterval, isPlaying playing: Bool) {
        seek(to: time)
        if playing { play() } else { pause() }
    }
}
