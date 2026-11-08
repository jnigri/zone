import SwiftUI

/// Shared by the main window and the menu bar panel. Settings and the tag filter
/// replace the session view in place; the back arrow (or Escape) returns.
struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @State private var screen = Screen.session

    private enum Screen { case session, settings, filter }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch screen {
            case .settings:
                SettingsView { screen = .session }
            case .filter:
                FilterView { screen = .session }
            case .session:
                VStack(spacing: 20) {
                    header
                    TimerRing(timer: state.timer)
                    DurationPicker()
                    TransportBar()
                    trackInfo
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .foregroundStyle(palette.text)
        .background(palette.background)
        .containerBackground(palette.background, for: .window)
        .onAppear { AppMode.openWindow = openWindow }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            IconButton(
                systemName: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                help: "Filter songs by tag",
                tint: filtering ? palette.accent : nil
            ) {
                screen = .filter
            }
            IconButton(systemName: "gearshape", help: "Settings") {
                screen = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            if showInMenuBar {
                IconButton(systemName: "power", help: "Quit Zone") {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private var filtering: Bool { state.music.isFiltering }

    @ViewBuilder
    private var trackInfo: some View {
        if state.music.tracks.isEmpty {
            HStack(spacing: 4) {
                Text("No tracks in folder.")
                    .foregroundStyle(palette.muted)
                Button("Choose…") { state.chooseFolder() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.link)
            }
            .font(.callout)
        } else if state.music.current == nil, state.music.playableTracks.isEmpty {
            HStack(spacing: 4) {
                Text("No songs match the filter.")
                    .foregroundStyle(palette.muted)
                Button("Edit…") { screen = .filter }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.link)
            }
            .font(.callout)
        } else {
            HStack(spacing: 2) {
                Label(
                    (state.music.current?.deletingPathExtension().lastPathComponent ?? "\(state.music.playableTracks.count) tracks ready")
                        + (state.music.focusModulation ? " · 16 Hz" : ""),
                    systemImage: "music.note"
                )
                .lineLimit(1)
                .truncationMode(.middle)
                if state.music.current != nil {
                    IconButton(systemName: "hand.thumbsdown", size: 12, help: "Don't play this song again") {
                        state.music.dislikeCurrent()
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(palette.muted)
        }
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 14
    let help: String
    /// Fixed color (e.g. accent for an active state); otherwise muted, brighter on hover.
    var tint: Color?
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? (hovering ? palette.text : palette.muted))
        .onHover { hovering = $0 }
        .help(help)
    }
}
