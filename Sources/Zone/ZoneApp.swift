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

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Logo.templateImage)
            if timer.phase == .running || timer.phase == .paused {
                Text(timer.remaining.compactString)
                    .monospacedDigit()
            }
        }
    }
}

enum AppMode {
    static let mainWindowID = "main"

    /// Menu bar mode hides the Dock icon; window mode shows it.
    static func applyActivationPolicy(menuBar: Bool) {
        NSApp.setActivationPolicy(menuBar ? .accessory : .regular)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppMode.applyActivationPolicy(menuBar: UserDefaults.standard.bool(forKey: Keys.showInMenuBar))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeMode.stored.apply()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        Notifier.requestAuthorization()
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
