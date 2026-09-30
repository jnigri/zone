import AppKit
import Observation
import UserNotifications

@Observable
final class AppState {
    static let presets: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60]

    let timer: SessionTimer
    let music = MusicPlayer()
    private(set) var folder: URL

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.duration)
        timer = SessionTimer(duration: stored > 0 ? stored : 30 * 60)
        folder = MusicLibrary.folder()
        music.reload(folder: folder)
        timer.onFinish = { [weak self] in self?.finishSession() }
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
    }

    func stop() {
        timer.reset()
        music.stop()
    }

    /// Picking a duration mid-session restarts the session with it; music keeps its track.
    func setDuration(_ value: TimeInterval) {
        let restart = isActive
        if restart { timer.reset() }
        timer.setDuration(value)
        UserDefaults.standard.set(timer.duration, forKey: Keys.duration)
        if restart {
            timer.start()
            music.play()
        }
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

    func rescanFolder() {
        music.reload(folder: folder)
    }

    private func finishSession() {
        music.fadeOut(over: 3) { [weak self] in self?.music.stop() }
        NSSound(named: "Glass")?.play()
        Notifier.sessionDone(duration: timer.duration)
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
