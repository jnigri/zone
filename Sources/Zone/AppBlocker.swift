import AppKit

/// Quits distracting apps while a session runs: any blocked app already open when the session
/// starts, and any that gets launched or brought to the front during it.
/// Apps are matched by bundle identifier and asked to quit politely, like ⌘Q.
final class AppBlocker {
    static let defaultApps = ""

    private var observers: [NSObjectProtocol] = []

    func update(active: Bool) {
        if active, observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification]
                .map { name in
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                        self?.quitIfBlocked(app)
                    }
                }
            NSWorkspace.shared.runningApplications.forEach(quitIfBlocked)
        } else if !active, !observers.isEmpty {
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            observers = []
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.blockApps) as? Bool ?? true
    }

    private func quitIfBlocked(_ app: NSRunningApplication) {
        guard isEnabled,
              let id = app.bundleIdentifier,
              StoredList.enabled(Keys.blockedApps, default: Self.defaultApps, disabledKey: Keys.disabledApps).contains(id)
        else { return }
        app.terminate()
    }

    /// Display name and icon of an installed app, or nil once it's been uninstalled.
    static func info(for id: String) -> (name: String, icon: NSImage)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                NSWorkspace.shared.icon(forFile: url.path))
    }

    /// Asks for apps to add; returns their bundle identifiers.
    static func pickApps(prompt: String = "Block") -> [String] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { $0 != Bundle.main.bundleIdentifier }
    }
}
