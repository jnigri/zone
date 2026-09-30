import SwiftUI

/// Shared by the main window and the menu bar panel. Settings replace the
/// session view in place; the back arrow (or Escape) returns.
struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView { showingSettings = false }
            } else {
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: Logo.templateImage)
                .renderingMode(.template)
                .foregroundStyle(palette.accent)
            Text("Zone")
                .font(.system(.headline, design: .rounded))
            Spacer()
            IconButton(systemName: "gearshape", help: "Settings") {
                showingSettings = true
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
        } else {
            Label(
                (state.music.current?.deletingPathExtension().lastPathComponent ?? "\(state.music.tracks.count) tracks ready")
                    + (state.music.focusModulation ? " · 16 Hz" : ""),
                systemImage: "music.note"
            )
            .font(.callout)
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 14
    let help: String
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
        .foregroundStyle(hovering ? palette.text : palette.muted)
        .onHover { hovering = $0 }
        .help(help)
    }
}
