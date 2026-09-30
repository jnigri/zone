import AVFoundation
import Observation

@Observable
final class MusicPlayer: NSObject, AVAudioPlayerDelegate {
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

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var history: [URL] = []
    @ObservationIgnored private var fadeGeneration = 0

    override init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.6
        isMuted = defaults.bool(forKey: Keys.muted)
        super.init()
    }

    private var effectiveVolume: Float { isMuted ? 0 : Float(volume) }

    func reload(folder: URL) {
        tracks = MusicLibrary.tracks(in: folder)
        queue = []
        history = history.filter(tracks.contains)
        if let current, !tracks.contains(current) { stop() }
    }

    func play() {
        fadeGeneration += 1
        isPlaying = true
        if let player {
            player.volume = effectiveVolume
            player.play()
        } else {
            advance()
        }
    }

    func pause() {
        fadeGeneration += 1
        isPlaying = false
        player?.pause()
    }

    func stop() {
        fadeGeneration += 1
        isPlaying = false
        player?.stop()
        player = nil
        current = nil
    }

    func next() {
        advance()
    }

    /// Restarts the current track if it has played for more than 3s, otherwise goes back one.
    func previous() {
        if let player, player.currentTime > 3 {
            player.currentTime = 0
            return
        }
        guard let previous = history.popLast() else {
            player?.currentTime = 0
            return
        }
        if let current { queue.insert(current, at: 0) }
        load(previous)
    }

    func fadeOut(over seconds: TimeInterval, then completion: @escaping () -> Void) {
        guard let player, isPlaying else { return completion() }
        fadeGeneration += 1
        let generation = fadeGeneration
        player.setVolume(0, fadeDuration: seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            // Skip if the user started/paused something while fading.
            guard let self, self.fadeGeneration == generation else { return }
            completion()
        }
    }

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
        player?.stop()
        current = url
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = effectiveVolume
            player.prepareToPlay()
            self.player = player
            if isPlaying { player.play() }
        } catch {
            // Unreadable file: drop it and move on.
            tracks.removeAll { $0 == url }
            player = nil
            current = nil
            if !tracks.isEmpty { advance() }
        }
    }

    private func applyVolume() {
        player?.volume = effectiveVolume
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.player, self.isPlaying else { return }
            self.advance()
        }
    }
}
