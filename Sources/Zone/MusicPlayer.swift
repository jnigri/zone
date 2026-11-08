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
    /// Tags per track, read from the files after each reload.
    private(set) var trackTags: [URL: [String]] = [:]
    /// Tags set to Include in the filter: when any are set, only songs having at least one of
    /// them play. Empty means every song can play.
    private(set) var includedTags: Set<String> {
        didSet { UserDefaults.standard.set(includedTags.sorted(), forKey: Keys.selectedTags) }
    }
    /// Tags set to Exclude: songs having any of them never play, even if they have an included tag.
    private(set) var excludedTags: Set<String> {
        didSet { UserDefaults.standard.set(excludedTags.sorted(), forKey: Keys.excludedTags) }
    }
    /// File names of songs marked "don't like": never picked by the shuffle. Names rather
    /// than paths so they survive moving the folder.
    private(set) var dislikedSongs: Set<String> {
        didSet { UserDefaults.standard.set(dislikedSongs.sorted(), forKey: Keys.dislikedSongs) }
    }
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
    @ObservationIgnored private var stream: TrackStream?

    // Position is tracked by wall clock so it survives engine restarts (device changes).
    @ObservationIgnored private var positionBase: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?

    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var history: [URL] = []
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var tagGeneration = 0
    @ObservationIgnored private var scheduleGeneration = 0
    @ObservationIgnored private var queuedBuffers = 0
    @ObservationIgnored private var fadeGeneration = 0
    @ObservationIgnored private var fadeTimer: Timer?

    /// Fired after playback state, track or position changes (used for Now Playing).
    @ObservationIgnored var onChange: (() -> Void)?

    var currentTime: TimeInterval {
        let elapsed = resumedAt.map { Date().timeIntervalSince($0) } ?? 0
        return min(trackDuration, positionBase + elapsed)
    }

    var trackDuration: TimeInterval { stream?.duration ?? 0 }

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.6
        isMuted = defaults.bool(forKey: Keys.muted)
        focusModulation = defaults.bool(forKey: Keys.focusModulation)
        modulationDepth = ModulationDepth(rawValue: defaults.string(forKey: Keys.modulationDepth) ?? "") ?? .medium
        includedTags = Set(defaults.stringArray(forKey: Keys.selectedTags) ?? [])
        excludedTags = Set(defaults.stringArray(forKey: Keys.excludedTags) ?? [])
        // The filter used to store tags switched off; that meaning is gone.
        defaults.removeObject(forKey: Keys.skippedTags)
        dislikedSongs = Set(defaults.stringArray(forKey: Keys.dislikedSongs) ?? [])

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
        loadTags(for: tracks)
    }

    // MARK: Tag filter

    /// Tracks the shuffle may pick: not disliked, no excluded tag, and an included tag when any are set.
    var playableTracks: [URL] { tracks.filter(isPlayable) }

    func isPlayable(_ url: URL) -> Bool {
        let tags = trackTags[url] ?? []
        return !isDisliked(url)
            && !tags.contains(where: excludedTags.contains)
            && (includedTags.isEmpty || tags.contains(where: includedTags.contains))
    }

    /// True when any tag is set to Include or Exclude.
    var isFiltering: Bool { !includedTags.isEmpty || !excludedTags.isEmpty }

    /// Every tag found in the folder with its song count, alphabetical.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tags in trackTags.values { for tag in tags { counts[tag, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.tag < $1.tag }
    }

    func mode(for tag: String) -> TagMode {
        includedTags.contains(tag) ? .include : excludedTags.contains(tag) ? .exclude : .normal
    }

    func setTag(_ tag: String, mode: TagMode) {
        changeFilter {
            includedTags.remove(tag)
            excludedTags.remove(tag)
            switch mode {
            case .include: includedTags.insert(tag)
            case .exclude: excludedTags.insert(tag)
            case .normal: break
            }
        }
    }

    func clearTags() {
        changeFilter {
            includedTags = []
            excludedTags = []
        }
    }

    /// Runs a filter change, then slots songs it newly allows into the upcoming queue.
    private func changeFilter(_ change: () -> Void) {
        let before = Set(playableTracks)
        change()
        applyFilter(allowed: playableTracks.filter { !before.contains($0) })
    }

    /// Keeps the shuffle order instead of reshuffling, so songs already heard this round
    /// don't come straight back: skipped songs leave the queue and newly `allowed` ones go
    /// in at random spots. A now-skipped current song gives way to the next playable one,
    /// and music resumes if the filter allows songs again.
    private func applyFilter(allowed: [URL] = []) {
        queue.removeAll { !isPlayable($0) }
        if !queue.isEmpty {
            for url in allowed where url != current {
                queue.insert(url, at: Int.random(in: 0...queue.count))
            }
        }
        if let current, !isPlayable(current) {
            if playableTracks.isEmpty {
                let wasPlaying = isPlaying
                stop()
                isPlaying = wasPlaying
            } else {
                advance()
            }
        } else if isPlaying, current == nil {
            advance()
        }
    }

    // MARK: Disliked songs

    func isDisliked(_ url: URL) -> Bool { dislikedSongs.contains(url.lastPathComponent) }

    /// Disliked songs present in the current folder, alphabetical.
    var dislikedTracks: [URL] { tracks.filter(isDisliked) }

    /// Drops the current song from rotation for good and moves on to the next one.
    func dislikeCurrent() {
        guard let current else { return }
        changeFilter { dislikedSongs.insert(current.lastPathComponent) }
    }

    func restore(_ url: URL) {
        changeFilter { dislikedSongs.remove(url.lastPathComponent) }
    }

    private func loadTags(for urls: [URL]) {
        tagGeneration += 1
        let generation = tagGeneration
        Task { @MainActor [weak self] in
            let tags = await withTaskGroup(of: (URL, [String]).self) { group in
                for url in urls { group.addTask { (url, await MusicLibrary.tags(for: url)) } }
                var result: [URL: [String]] = [:]
                for await (url, tags) in group { result[url] = tags }
                return result
            }
            guard let self, self.tagGeneration == generation else { return }
            self.trackTags = tags
            self.applyFilter()
        }
    }

    func play() {
        cancelFade()
        isPlaying = true
        if stream != nil {
            startNode()
        } else if current == nil {
            advance()
        }
        // Otherwise a track is still opening; it starts once loaded.
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
        loadGeneration += 1
        scheduleGeneration += 1
        node.stop()
        engine.stop()
        stream = nil
        current = nil
        positionBase = 0
        resumedAt = nil
        onChange?()
    }

    func next() {
        advance()
    }

    /// Restarts the current track if it has played for more than 3s, otherwise goes back
    /// one, passing over songs the filter now skips.
    func previous() {
        if stream != nil, currentTime > 3 {
            restartTrack()
            return
        }
        history.removeAll { !isPlayable($0) }
        guard let previous = history.popLast() else {
            restartTrack()
            return
        }
        if let current, isPlayable(current) { queue.insert(current, at: 0) }
        load(previous)
    }

    func fadeOut(over seconds: TimeInterval, then completion: @escaping () -> Void) {
        guard stream != nil, isPlaying else { return completion() }
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
            queue = playableTracks.shuffled()
            // Avoid replaying the same track right after a reshuffle.
            if queue.count > 1, queue.first == current { queue.swapAt(0, 1) }
        }
        guard !queue.isEmpty else { return }
        if let current, isPlayable(current) { history.append(current) }
        load(queue.removeFirst())
    }

    /// Opening a track is async; a newer load or a stop supersedes a pending one.
    private func load(_ url: URL) {
        loadGeneration += 1
        let generation = loadGeneration
        scheduleGeneration += 1
        node.stop()
        stream = nil
        current = url
        positionBase = 0
        resumedAt = nil

        Task { @MainActor [weak self] in
            do {
                let stream = try await TrackStream.open(url)
                guard let self, self.loadGeneration == generation else { return }
                self.connect(format: stream.format)
                self.stream = stream
                self.schedule(from: 0)
                if self.isPlaying { self.startNode() }
                self.onChange?()
            } catch {
                // Unreadable file: drop it and move on.
                guard let self, self.loadGeneration == generation else { return }
                self.tracks.removeAll { $0 == url }
                self.current = nil
                if !self.tracks.isEmpty { self.advance() }
            }
        }
    }

    private func restartTrack() {
        guard stream != nil else { return }
        schedule(from: 0)
        if isPlaying { startNode() }
        onChange?()
    }

    /// Plays the current track from `seconds` onward, keeping a few decoded chunks queued
    /// (~1.4 s). Stopping the node fires pending completions too, so completions carry a
    /// generation and stale ones are ignored.
    private func schedule(from seconds: TimeInterval) {
        guard let stream else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        node.stop()
        positionBase = seconds
        resumedAt = nil
        queuedBuffers = 0

        do { try stream.seek(to: seconds) } catch { return }
        for _ in 0..<4 { scheduleNextBuffer(generation: generation) }
    }

    private func scheduleNextBuffer(generation: Int) {
        guard let stream, generation == scheduleGeneration else { return }
        guard let buffer = stream.nextBuffer() else {
            // Decoder is done; the track ends once the last queued chunk has played.
            if queuedBuffers == 0, isPlaying { advance() }
            return
        }
        queuedBuffers += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.scheduleGeneration == generation else { return }
                self.queuedBuffers -= 1
                self.scheduleNextBuffer(generation: generation)
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
        guard stream != nil else { return }
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

/// What the filter does with songs carrying a tag: Only, Skip, or nothing.
enum TagMode {
    case include, normal, exclude
}
