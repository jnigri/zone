import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Keys.showInMenuBar) private var showInMenuBar = false
    @AppStorage(Keys.theme) private var theme: ThemeMode = .system

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Text("Zone lives next to the clock and hides its Dock icon.")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }

            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Music") {
                LabeledContent("Folder") {
                    Text(state.folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(palette.muted)
                }
                HStack {
                    Text("\(state.music.tracks.count) tracks")
                        .foregroundStyle(palette.muted)
                    Spacer()
                    Button("Rescan") { state.rescanFolder() }
                    Button("Choose…") { state.chooseFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: showInMenuBar) { _, menuBar in
            AppMode.applyActivationPolicy(menuBar: menuBar)
            if menuBar {
                dismissWindow(id: AppMode.mainWindowID)
            } else {
                openWindow(id: AppMode.mainWindowID)
            }
            NSApp.activate()
        }
        .onChange(of: theme) { _, mode in mode.apply() }
    }
}
