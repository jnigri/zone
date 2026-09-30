import AppKit
import SwiftUI
import UserNotifications

@main
struct ZoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @State private var state: AppState

    init() {
        // Used by scripts/build-app.sh: `Zone --render-icon <logo.png> <out.iconset>`.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 2 < args.count {
            do {
                try Logo.renderIconSet(
                    logo: URL(fileURLWithPath: args[i + 1]),
                    to: URL(fileURLWithPath: args[i + 2])
                )
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        }
        _state = State(initialValue: AppState())
    }

    var body: some Scene {
        Window("Zone", id: AppMode.mainWindowID) {
            MainView()
                .environment(state)
                .themed()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(showInMenuBar ? .suppressed : .presented)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MainView()
                .environment(state)
                .themed()
        } label: {
            MenuBarLabel(timer: state.timer)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let timer: SessionTimer

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Logo.templateImage)
            if timer.phase == .running || timer.phase == .paused {
                // Leading space: the menu bar ignores HStack spacing between icon and title.
                Text(" " + timer.remaining.compactString)
                    .monospacedDigit()
            }
        }
        .onAppear { AppMode.openWindow = openWindow }
    }
}

enum AppMode {
    static let mainWindowID = "main"

    /// Captured from live views so the main window can be reopened from app-level code.
    static var openWindow: OpenWindowAction?

    /// Menu bar mode hides the Dock icon; window mode shows it.
    static func applyActivationPolicy(menuBar: Bool) {
        NSApp.setActivationPolicy(menuBar ? .accessory : .regular)
    }

    /// Driven by the stored setting (see AppDelegate), not by the toggle's view:
    /// the toggle lives inside the very window/panel this closes.
    static func switchTo(menuBar: Bool) {
        applyActivationPolicy(menuBar: menuBar)
        if menuBar {
            mainWindow?.close()
        } else {
            if let window = mainWindow {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow?(id: mainWindowID)
            }
            NSApp.activate()
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            guard let id = window.identifier?.rawValue else { return false }
            return id == mainWindowID || id.hasPrefix(mainWindowID + "-")
        }
    }
}

extension UserDefaults {
    /// KVO-observable mirror of the showInMenuBar key (name must match the key).
    @objc dynamic var showInMenuBar: Bool { bool(forKey: Keys.showInMenuBar) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppMode.applyActivationPolicy(menuBar: UserDefaults.standard.bool(forKey: Keys.showInMenuBar))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeMode.stored.apply()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        Notifier.requestAuthorization()

        menuBarObservation = UserDefaults.standard.observe(\.showInMenuBar, options: [.old, .new]) { _, change in
            guard let menuBar = change.newValue, menuBar != change.oldValue else { return }
            // Next run loop turn: let SwiftUI finish updating the toggle and scenes first.
            DispatchQueue.main.async { AppMode.switchTo(menuBar: menuBar) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Show the banner even while Zone is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
