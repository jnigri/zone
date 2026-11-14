import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation

/// When typing makes switch sounds.
enum KeySoundMode: String, CaseIterable, Identifiable {
    case off, sessions, always

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .sessions: "In sessions"
        case .always: "Always"
        }
    }
}

/// Plays mechanical keyboard sounds as you type, anywhere on the Mac.
///
/// Keys are heard through a listen-only event tap, which needs the Input Monitoring permission.
/// Zone only asks for it when the user turns the sounds on, never at launch.
/// Typing stays silent in password fields (macOS secure input) and in the quiet apps list.
@Observable
final class KeySounds {
    /// Random pitch shift per keystroke, in semitones either way.
    static let pitchSteps: [Double] = [0, 2.5, 5, 7.5, 10]

    /// Password managers that are quiet out of the box, kept to the ones installed.
    static var defaultQuietApps: String {
        let candidates = [
            "com.bitwarden.desktop",
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.apple.Passwords",
            "com.apple.keychainaccess",
        ]
        return StoredList.string(candidates.filter { AppBlocker.info(for: $0) != nil })
    }

    var mode: KeySoundMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.keySounds)
            refresh(askPermission: true)
        }
    }

    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.keySoundVolume)
            engine.mainMixerNode.outputVolume = Float(volume)
        }
    }

    var pitchVariation: Double {
        didSet { UserDefaults.standard.set(pitchVariation, forKey: Keys.keySoundPitch) }
    }

    /// Sounds are on but macOS hasn't granted Input Monitoring.
    private(set) var needsPermission = false

    @ObservationIgnored private var sessionRunning = false
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var tapSource: CFRunLoopSource?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var voices: [(player: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed)] = []
    @ObservationIgnored private var nextVoice = 0
    @ObservationIgnored private var pack: KeySoundPack?
    /// Audio work runs here so the event tap never waits on it.
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "Zone.KeySounds")

    init() {
        let defaults = UserDefaults.standard
        mode = KeySoundMode(rawValue: defaults.string(forKey: Keys.keySounds) ?? "") ?? .off
        volume = defaults.object(forKey: Keys.keySoundVolume) as? Double ?? 0.5
        pitchVariation = defaults.object(forKey: Keys.keySoundPitch) as? Double ?? 2.5
        engine.mainMixerNode.outputVolume = Float(volume)

        // Permission granted in System Settings takes effect when the user comes back to Zone.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartEngine() }

        refresh()
    }

    deinit {
        stopListening()
    }

    func update(sessionRunning: Bool) {
        self.sessionRunning = sessionRunning
        refresh()
    }

    /// Starts or stops listening to match the mode, session and permission.
    /// Only a user turning the sounds on passes `askPermission`, so launch never shows a prompt.
    func refresh(askPermission: Bool = false) {
        guard mode != .off else {
            needsPermission = false
            stopListening()
            return
        }
        guard CGPreflightListenEventAccess() else {
            // macOS shows its prompt only the first time; after that the user goes to System Settings.
            if askPermission { CGRequestListenEventAccess() }
            needsPermission = true
            stopListening()
            return
        }
        needsPermission = false
        if mode == .always || sessionRunning {
            startListening()
        } else {
            stopListening()
        }
    }

    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    // MARK: Listening

    private func startListening() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<KeySounds>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            // AppState owns this object for the app's lifetime, and deinit removes the tap.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            needsPermission = true
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
        audioQueue.async { [self] in startEngine() }
    }

    private func stopListening() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        audioQueue.async { [engine] in engine.stop() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isDown: Bool
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .keyDown:
            // Holding a key repeats it; a real switch only clicks once.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            isDown = true
        case .keyUp:
            isDown = false
        case .flagsChanged:
            guard let mask = Self.modifierMask(keyCode) else { return }
            isDown = event.flags.contains(mask)
        default:
            return
        }
        guard !isQuiet else { return }
        play(keyCode: keyCode, isDown: isDown)
    }

    /// Password fields turn on secure input. macOS then hides most keys from the tap, but not
    /// modifiers like Shift, so this check keeps those silent too.
    private var isQuiet: Bool {
        if IsSecureEventInputEnabled() { return true }
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return StoredList.enabled(Keys.quietApps, default: Self.defaultQuietApps, disabledKey: Keys.disabledQuietApps)
            .contains(id)
    }

    /// The flag that tells whether this modifier key is now down, per side of the keyboard.
    private static func modifierMask(_ keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54: CGEventFlags(rawValue: 0x10) // right command
        case 55: CGEventFlags(rawValue: 0x08) // left command
        case 56: CGEventFlags(rawValue: 0x02) // left shift
        case 60: CGEventFlags(rawValue: 0x04) // right shift
        case 58: CGEventFlags(rawValue: 0x20) // left option
        case 61: CGEventFlags(rawValue: 0x40) // right option
        case 59: CGEventFlags(rawValue: 0x01) // left control
        case 62: CGEventFlags(rawValue: 0x2000) // right control
        case 57: .maskAlphaShift // caps lock
        case 63: .maskSecondaryFn
        default: nil
        }
    }

    // MARK: Playback

    private func play(keyCode: Int64, isDown: Bool) {
        let semitones = pitchVariation > 0 ? Double.random(in: -pitchVariation...pitchVariation) : 0
        let rate = Float(pow(2, semitones / 12))
        audioQueue.async { [self] in
            guard engine.isRunning, !voices.isEmpty,
                  let buffer = pack?.sound(for: KeySoundPack.key(for: keyCode), isDown: isDown)
            else { return }
            let voice = voices[nextVoice]
            nextVoice = (nextVoice + 1) % voices.count
            voice.player.stop()
            voice.varispeed.rate = rate
            voice.player.scheduleBuffer(buffer)
            voice.player.play()
        }
    }

    /// Runs on `audioQueue`. Sounds load on first use, so Zone with sounds off never reads them.
    private func startEngine() {
        if pack == nil {
            guard let url = Bundle.main.resourceURL?.appending(path: "KeySounds/Cream", directoryHint: .isDirectory),
                  let loaded = KeySoundPack(folder: url)
            else { return }
            pack = loaded
            // Enough voices for fast typing, so one click never cuts off the one before.
            for _ in 0..<12 {
                let voice = (player: AVAudioPlayerNode(), varispeed: AVAudioUnitVarispeed())
                engine.attach(voice.player)
                engine.attach(voice.varispeed)
                engine.connect(voice.player, to: voice.varispeed, format: loaded.format)
                engine.connect(voice.varispeed, to: engine.mainMixerNode, format: loaded.format)
                voices.append(voice)
            }
        }
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    /// The output device changed (headphones, AirPods): the engine stopped and needs a restart.
    private func restartEngine() {
        guard tap != nil else { return }
        audioQueue.async { [self] in startEngine() }
    }
}

/// A Thock-format sound pack: a folder of sounds and a config.json naming them per key.
struct KeySoundPack {
    let format: AVAudioFormat
    private let down: [String: [AVAudioPCMBuffer]]
    private let up: [String: [AVAudioPCMBuffer]]

    private struct Config: Decodable {
        let sounds: [String: Sounds]
        struct Sounds: Decodable {
            let down: [String]
            let up: [String]
        }
    }

    init?(folder: URL) {
        guard let data = try? Data(contentsOf: folder.appending(path: "config.json")),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }

        func load(_ names: [String]) -> [AVAudioPCMBuffer] {
            names.compactMap { name in
                guard let file = try? AVAudioFile(forReading: folder.appending(path: name)),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil
                else { return nil }
                return buffer
            }
        }
        down = config.sounds.mapValues { load($0.down) }
        up = config.sounds.mapValues { load($0.up) }
        // All voices share one format; sound(for:) skips any file recorded in another.
        guard let format = down["default"]?.first?.format else { return nil }
        self.format = format
    }

    /// The pack's name for a key: a few keys have their own sound, the rest share "default".
    static func key(for keyCode: Int64) -> String {
        switch keyCode {
        case 49: "space"
        case 36, 76: "enter"
        case 51: "backspace"
        default: "default"
        }
    }

    func sound(for key: String, isDown: Bool) -> AVAudioPCMBuffer? {
        let sounds = isDown ? down : up
        let matching = (sounds[key]?.isEmpty == false ? sounds[key] : sounds["default"])?
            .filter { $0.format == format }
        return matching?.randomElement()
    }
}
