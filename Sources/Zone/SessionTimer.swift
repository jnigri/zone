import Foundation
import Observation

@Observable
final class SessionTimer {
    enum Phase { case idle, running, paused, finished }

    /// Duration for open-ended sessions: the timer counts up and never finishes.
    static let infinite = TimeInterval.infinity

    private(set) var duration: TimeInterval
    private(set) var elapsed: TimeInterval = 0
    private(set) var phase: Phase = .idle

    @ObservationIgnored var onFinish: (() -> Void)?
    /// Elapsed time banked before the current run; plus wall-clock time since `resumedAt`,
    /// so sleep or run loop stalls don't cause drift.
    @ObservationIgnored private var banked: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var ticker: Timer?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var isInfinite: Bool { duration.isInfinite }

    var remaining: TimeInterval { max(0, duration - elapsed) }

    /// What the clock shows: time left, or time elapsed when open-ended.
    var displayTime: TimeInterval { isInfinite ? elapsed : remaining }

    /// Ring fill. Open-ended sessions fill once per hour, then start over.
    var progress: Double {
        if isInfinite { return elapsed.truncatingRemainder(dividingBy: 3600) / 3600 }
        guard duration > 0 else { return 0 }
        return min(1, elapsed / duration)
    }

    var canChangeDuration: Bool { phase == .idle || phase == .finished }

    func setDuration(_ value: TimeInterval) {
        guard canChangeDuration, value > 0 else { return }
        duration = value
        elapsed = 0
        phase = .idle
    }

    func start() {
        if phase == .idle || phase == .finished {
            banked = 0
            elapsed = 0
        }
        resumedAt = Date()
        phase = .running
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func pause() {
        guard phase == .running else { return }
        tick()
        banked = elapsed
        stopTicker()
        phase = .paused
    }

    func reset() {
        stopTicker()
        banked = 0
        elapsed = 0
        phase = .idle
    }

    private func tick() {
        guard let resumedAt else { return }
        elapsed = banked + Date().timeIntervalSince(resumedAt)
        if !isInfinite, elapsed >= duration {
            elapsed = duration
            stopTicker()
            phase = .finished
            onFinish?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        resumedAt = nil
    }
}

extension TimeInterval {
    /// "mm:ss", or "h:mm:ss" past an hour. Counting down rounds up so the display
    /// never shows 00:00 early; counting up rounds down so it doesn't run ahead.
    func clockString(countingUp: Bool = false) -> String {
        let total = Int(self.rounded(countingUp ? .down : .up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// Compact form for the menu bar: minutes left rounded to nearest, halves down
    /// ("15m" for 14:31, "14m" for 14:30), "2h05" past 90 minutes,
    /// or "45s" in the last minute.
    func compactString(countingUp: Bool = false) -> String {
        let total = Int(self.rounded(countingUp ? .down : .up))
        guard total >= 60 else { return "\(total)s" }
        let minutes = (total + 29) / 60
        return minutes > 90 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    /// Human duration label: "15m", "1h", "1h 20m", "45s", "2m 30s", "∞".
    var durationLabel: String {
        guard isFinite else { return "∞" }
        let total = Int(self.rounded())
        let parts = [(total / 3600, "h"), ((total % 3600) / 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
