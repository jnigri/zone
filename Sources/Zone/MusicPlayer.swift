import AVFoundation
import Observation

enum ModulationDepth: String, CaseIterable, Identifiable {
    case subtle, medium, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    /// How far the 200 Hz–1 kHz band dips at the bottom of each pulse.
    var value: Float {
        switch self {
        case .subtle: 0.3
        case .medium: 0.5
        case .strong: 0.7
        }
    }
}

/// Plays tracks through AVAudioEngine: player node → focus modulator → main mixer.
@Observable
final class MusicPlayer {
    private(set) var tracks: [URL] = []
    private(set) var current: URL?
    private(set) var isPlaying = false

    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.volume)
            applyVolume()
        }
    }

    var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Keys.muted)
            applyVolume()
        }
    }

    var focusModulation: Bool {
        didSet {
            UserDefaults.standard.set(focusModulation, forKey: Keys.focusModulation)
            applyModulation()
        }
    }

    var modulationDepth: ModulationDepth {
        didSet {
            UserDefaults.standard.set(modulationDepth.rawValue, forKey: Keys.modulationDepth)
            applyModulation()
        }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private let modulator = FocusModulatorUnit.makeNode()
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    @ObservationIgnored private var file: AVAudioFile?

    // Position is tracked by wall clock so it survives engine restarts (device changes).
    @ObservationIgnored private var positionBase: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?

    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var history: [URL] = []
    @ObservationIgnored private var scheduleGeneration = 0
    @ObservationIgnored private var fadeGeneration = 0
    @ObservationIgnored private var fadeTimer: Timer?

    /// Fired after playback state, track or position changes (used for Now Playing).
    @ObservationIgnored var onChange: (() -> Void)?

    var currentTime: TimeInterval {
        let elapsed = resumedAt.map { Date().timeIntervalSince($0) } ?? 0
        return min(trackDuration, positionBase + elapsed)
    }

    var trackDuration: TimeInterval {
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.6
        isMuted = defaults.bool(forKey: Keys.muted)
        focusModulation = defaults.bool(forKey: Keys.focusModulation)
        modulationDepth = ModulationDepth(rawValue: defaults.string(forKey: Keys.modulationDepth) ?? "") ?? .medium

        engine.attach(node)
        engine.attach(modulator)
        applyVolume()
        applyModulation()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.handleConfigurationChange() }
    }

    private var effectiveVolume: Float { isMuted ? 0 : Float(volume) }

    func reload(folder: URL) {
        tracks = MusicLibrary.tracks(in: folder)
        queue = []
        history = history.filter(tracks.contains)
        if let current, !tracks.contains(current) { stop() }
    }

    func play() {
        cancelFade()
        isPlaying = true
        if file != nil {
            startNode()
        } else {
            advance()
        }
        onChange?()
    }

    func pause() {
        cancelFade()
        isPlaying = false
        pauseNode()
        onChange?()
    }

    func stop() {
        cancelFade()
        isPlaying = false
        scheduleGeneration += 1
        node.stop()
        engine.stop()
        file = nil
        current = nil
        positionBase = 0
        resumedAt = nil
        onChange?()
    }

    func next() {
        advance()
    }

    /// Restarts the current track if it has played for more than 3s, otherwise goes back one.
    func previous() {
        if file != nil, currentTime > 3 {
            restartTrack()
            return
        }
        guard let previous = history.popLast() else {
            restartTrack()
            return
        }
        if let current { queue.insert(current, at: 0) }
        load(previous)
    }

    func fadeOut(over seconds: TimeInterval, then completion: @escaping () -> Void) {
        guard file != nil, isPlaying else { return completion() }
        cancelFade()
        let generation = fadeGeneration
        let startVolume = node.volume
        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            // Stop if the user started/paused something while fading.
            guard let self, self.fadeGeneration == generation else { return timer.invalidate() }
            let progress = min(1, Date().timeIntervalSince(start) / seconds)
            self.node.volume = startVolume * Float(1 - progress)
            if progress >= 1 {
                timer.invalidate()
                self.fadeTimer = nil
                completion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    // MARK: Playback internals

    private func advance() {
        if queue.isEmpty {
            queue = tracks.shuffled()
            // Avoid replaying the same track right after a reshuffle.
            if queue.count > 1, queue.first == current { queue.swapAt(0, 1) }
        }
        guard !queue.isEmpty else { return }
        if let current { history.append(current) }
        load(queue.removeFirst())
    }

    private func load(_ url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            node.stop()
            connect(format: file.processingFormat)
            self.file = file
            current = url
            schedule(from: 0)
            if isPlaying { startNode() }
            onChange?()
        } catch {
            // Unreadable file: drop it and move on.
            tracks.removeAll { $0 == url }
            if !tracks.isEmpty { advance() }
        }
    }

    private func restartTrack() {
        guard file != nil else { return }
        schedule(from: 0)
        if isPlaying { startNode() }
        onChange?()
    }

    /// Queues the current file from `seconds` onward. Stopping the node fires the previous
    /// segment's completion too, so completions carry a generation and stale ones are ignored.
    private func schedule(from seconds: TimeInterval) {
        guard let file else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        node.stop()
        positionBase = seconds
        resumedAt = nil

        let startFrame = AVAudioFramePosition(seconds * file.processingFormat.sampleRate)
        guard startFrame < file.length else { return }
        node.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(file.length - startFrame),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.scheduleGeneration == generation, self.isPlaying else { return }
                self.advance()
            }
        }
    }

    private func startNode() {
        applyVolume()
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        node.play()
        if resumedAt == nil { resumedAt = Date() }
    }

    private func pauseNode() {
        positionBase = currentTime
        resumedAt = nil
        node.pause()
    }

    /// Mono and stereo files need different connection formats; rewire only when it changes.
    private func connect(format: AVAudioFormat) {
        guard connectedFormat != format else { return }
        let wasRunning = engine.isRunning
        engine.stop()
        engine.disconnectNodeOutput(node)
        engine.disconnectNodeOutput(modulator)
        engine.connect(node, to: modulator, format: format)
        engine.connect(modulator, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        if wasRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    /// Output device changed (headphones, AirPods…): the engine stopped, so resume where we were.
    private func handleConfigurationChange() {
        guard file != nil else { return }
        let position = currentTime
        schedule(from: position)
        if isPlaying { startNode() }
    }

    private func cancelFade() {
        fadeGeneration += 1
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func applyVolume() {
        node.volume = effectiveVolume
    }

    private func applyModulation() {
        guard let unit = modulator.auAudioUnit as? FocusModulatorUnit else { return }
        unit.targetDepth.pointee = focusModulation ? modulationDepth.value : 0
    }
}
