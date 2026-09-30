import Foundation
import Observation

@Observable
final class SessionTimer {
    enum Phase { case idle, running, paused, finished }

    private(set) var duration: TimeInterval
    private(set) var remaining: TimeInterval
    private(set) var phase: Phase = .idle

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?

    init(duration: TimeInterval) {
        self.duration = duration
        self.remaining = duration
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining / duration
    }

    var canChangeDuration: Bool { phase == .idle || phase == .finished }

    func setDuration(_ value: TimeInterval) {
        guard canChangeDuration, value > 0 else { return }
        duration = value
        remaining = value
        phase = .idle
    }

    func start() {
        if phase == .idle || phase == .finished { remaining = duration }
        // Track an absolute end date so sleep or run loop stalls don't cause drift.
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func pause() {
        guard phase == .running else { return }
        tick()
        stopTicker()
        phase = .paused
    }

    func reset() {
        stopTicker()
        remaining = duration
        phase = .idle
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicker()
            phase = .finished
            onFinish?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }
}

extension TimeInterval {
    /// "mm:ss", or "h:mm:ss" past an hour. Rounds up so the display never shows 00:00 early.
    var clockString: String {
        let total = Int(self.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// Compact form for the menu bar: minutes left rounded to nearest, halves down
    /// ("15m" for 14:31, "14m" for 14:30), "h:mm" past 90 minutes ("2:05"),
    /// or "45s" in the last minute.
    var compactString: String {
        let total = Int(self.rounded(.up))
        guard total >= 60 else { return "\(total)s" }
        let minutes = (total + 29) / 60
        return minutes > 90 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    /// Human duration label: "15m", "1h", "1h 20m", "45s", "2m 30s".
    var durationLabel: String {
        let total = Int(self.rounded())
        let parts = [(total / 3600, "h"), ((total % 3600) / 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
