import SwiftUI

/// Settings screen shown in place of the session view (window and menu bar panel).
struct SettingsView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @AppStorage(Keys.theme) private var theme: ThemeMode = .system
    @AppStorage(Keys.blockSites) private var blockSites = true
    @AppStorage(Keys.blockedSites) private var blockedSites = SiteBlocker.defaultSites
    @AppStorage(Keys.blockApps) private var blockApps = true
    @AppStorage(Keys.blockedApps) private var blockedApps = AppBlocker.defaultApps
    @AppStorage(Keys.keepAwake) private var keepAwake = true

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
                Toggle("Keep Mac awake during sessions", isOn: $keepAwake)
                    .onChange(of: keepAwake) { state.keepAwakeChanged() }
                caption("The screen stays on and won't lock while a session runs. Pausing lets it sleep again.")
            }

            card {
                Toggle("Block sites during sessions", isOn: $blockSites)
                // TextEditor, not a vertical TextField: on macOS Return ends editing in a TextField.
                TextEditor(text: $blockedSites)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .padding(6)
                    .frame(height: 90)
                    .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.raised, lineWidth: 1))
                    .disabled(!blockSites)
                    .opacity(blockSites ? 1 : 0.5)
                caption("One domain per line. Works in Safari, Chrome, Arc, Brave, Edge and Vivaldi. macOS asks once per browser for permission.")
            }

            card {
                Toggle("Quit apps during sessions", isOn: $blockApps)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(AppBlocker.ids(blockedApps), id: \.self) { id in
                        let info = AppBlocker.info(for: id)
                        HStack(spacing: 8) {
                            if let icon = info?.icon {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(info?.name ?? id)
                                .lineLimit(1)
                            Spacer()
                            IconButton(systemName: "xmark", size: 10, help: "Remove") {
                                blockedApps = AppBlocker.ids(blockedApps).filter { $0 != id }.joined(separator: "\n")
                            }
                        }
                    }
                    Button("Add App…") {
                        let ids = AppBlocker.ids(blockedApps)
                        blockedApps = (ids + AppBlocker.pickApps().filter { !ids.contains($0) }).joined(separator: "\n")
                    }
                    .controlSize(.small)
                }
                .disabled(!blockApps)
                .opacity(blockApps ? 1 : 0.5)
                caption("Zone quits these apps when a session starts, and again if you open them during it.")
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
