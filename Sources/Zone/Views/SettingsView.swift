import SwiftUI

/// Settings screen shown in place of the session view (window and menu bar panel).
struct SettingsView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @AppStorage(Keys.theme) private var theme: ThemeMode = .system

    var body: some View {
        @Bindable var music = state.music

        VStack(alignment: .leading, spacing: 14) {
            header

            card {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                caption("Zone lives next to the clock and hides its Dock icon.")
            }

            card {
                row("Theme") {
                    Picker("Theme", selection: $theme) {
                        ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            card {
                Toggle("Focus modulation (16 Hz)", isOn: $music.focusModulation)
                Picker("Intensity", selection: $music.modulationDepth) {
                    ForEach(ModulationDepth.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!music.focusModulation)
                caption("Gently pulses the mid-range of your music 16 times a second. Brain activity tends to sync with this rhythm, which is linked to sustained attention, helping you stay on task. Helps most if focusing is usually hard for you.")
            }

            card {
                row("Music") {
                    Text("\(music.tracks.count) tracks")
                        .foregroundStyle(palette.muted)
                }
                Text(state.folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack {
                    Button("Rescan") { state.rescanFolder() }
                    Button("Choose…") { state.chooseFolder() }
                }
                .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onExitCommand(perform: onBack)
        .onChange(of: theme) { _, mode in mode.apply() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "chevron.left", help: "Back") { onBack() }
            Text("Settings")
                .font(.system(.headline, design: .rounded))
            Spacer()
        }
        .padding(.leading, -8)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
