import SwiftUI

/// Shared by the main window and the menu bar panel. Settings and the music picker
/// replace the session view in place; the back arrow (or Escape) returns.
struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @State private var screen = Screen.session
    /// Settings scrolls within this height so switching screens doesn't resize the window.
    @State private var sessionHeight: CGFloat = 480

    private enum Screen { case session, settings, music }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch screen {
            case .settings:
                SettingsView { screen = .session }
                    .frame(height: sessionHeight)
            case .music:
                MusicView { screen = .session }
                    .frame(height: sessionHeight, alignment: .top)
            case .session:
                VStack(spacing: 20) {
                    header
                    TimerRing(timer: state.timer)
                    DurationPicker()
                    TransportBar()
                    trackInfo
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sessionHeight = $0 }
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
            MoodSwitch()
            Spacer()
            IconButton(
                systemName: "music.note.list",
                help: state.music.isFiltering ? "Tag filter on. Filter by tag, see disliked songs"
                    : "Filter by tag, see disliked songs",
                tint: state.music.isFiltering ? palette.accent : nil
            ) {
                screen = .music
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
                Text("No \(state.music.mood.title) songs here.")
                    .foregroundStyle(palette.muted)
                Button("Change…") { screen = .music }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.link)
            }
            .font(.callout)
        } else {
            HStack(spacing: 2) {
                Label(
                    (state.music.current.map(state.music.title) ?? "\(state.music.playableTracks.count) tracks ready")
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

/// Cruise or Beast Mode, side by side in one capsule. The current one shows its name; the
/// other shows only its icon, so the switch stays narrow.
private struct MoodSwitch: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let current = state.music.mood
        HStack(spacing: 2) {
            ForEach(Mood.allCases) { mood in
                let selected = mood == current
                Button {
                    withAnimation(.snappy(duration: 0.2)) { state.music.setMood(mood) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mood.symbol)
                            .foregroundStyle(selected ? palette.accent : palette.muted)
                        if selected {
                            Text(mood.title).lineLimit(1)
                        }
                    }
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .padding(.horizontal, selected ? 10 : 8)
                    .padding(.vertical, 4)
                    .background(selected ? palette.raised : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(mood.title): \(mood.subtitle.lowercased())")
                .accessibilityLabel(mood.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(palette.panel, in: Capsule())
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
