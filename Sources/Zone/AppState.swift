import AppKit
import Observation
import UserNotifications

@Observable
final class AppState {
    static let presets: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60]

    let timer: SessionTimer
    let music = MusicPlayer()
    let keySounds = KeySounds()
    @ObservationIgnored private let blocker = SiteBlocker()
    @ObservationIgnored private let appBlocker = AppBlocker()
    @ObservationIgnored private let caffeinator = Caffeinator()
    private(set) var folder: URL
    @ObservationIgnored private var nowPlaying: NowPlaying?

    init() {
        // Stored as seconds; -1 means open-ended (property lists can't hold infinity).
        let stored = UserDefaults.standard.double(forKey: Keys.duration)
        timer = SessionTimer(duration: stored == -1 ? SessionTimer.infinite : stored > 0 ? stored : 30 * 60)
        folder = MusicLibrary.folder()
        music.reload(folder: folder)
        timer.onFinish = { [weak self] in self?.finishSession() }
        nowPlaying = NowPlaying(state: self)
        music.onChange = { [weak self] in self?.syncNowPlaying() }
    }

    var isActive: Bool { timer.phase == .running || timer.phase == .paused }

    /// One button drives both the countdown and the music.
    func togglePlay() {
        if timer.phase == .running {
            timer.pause()
            music.pause()
        } else {
            timer.start()
            music.play()
        }
        syncNowPlaying()
    }

    func stop() {
        timer.reset()
        music.stop()
        syncNowPlaying()
    }

    /// Picking a duration mid-session restarts the session with it; music keeps its track.
    func setDuration(_ value: TimeInterval) {
        let restart = isActive
        if restart { timer.reset() }
        timer.setDuration(value)
        UserDefaults.standard.set(timer.isInfinite ? -1 : timer.duration, forKey: Keys.duration)
        if restart {
            timer.start()
            music.play()
        }
        syncNowPlaying()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Use Folder"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        MusicLibrary.save(url)
        folder = url
        music.reload(folder: url)
    }

    /// Applies the keep-awake setting to a session already running.
    func keepAwakeChanged() {
        caffeinator.update(active: timer.phase == .running)
    }

    func rescanFolder() {
        music.reload(folder: folder)
    }

    private func finishSession() {
        music.fadeOut(over: 3) { [weak self] in self?.music.stop() }
        NSSound(named: "Glass")?.play()
        Notifier.sessionDone(duration: timer.duration)
        syncNowPlaying()
    }

    private func syncNowPlaying() {
        nowPlaying?.update(from: self)
        blocker.update(active: timer.phase == .running)
        appBlocker.update(active: timer.phase == .running)
        caffeinator.update(active: timer.phase == .running)
        keySounds.update(sessionRunning: timer.phase == .running)
    }
}

enum Notifier {
    /// UNUserNotificationCenter traps outside an app bundle (e.g. `swift run`).
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func sessionDone(duration: TimeInterval) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Zone session done"
        content.body = "You stayed in the zone for \(duration.durationLabel)."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
