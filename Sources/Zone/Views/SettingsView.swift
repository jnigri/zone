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
    @AppStorage(Keys.disabledSites) private var disabledSites = ""
    @AppStorage(Keys.disabledApps) private var disabledApps = ""
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.quietApps) private var quietApps = KeySounds.defaultQuietApps
    @AppStorage(Keys.disabledQuietApps) private var disabledQuietApps = ""
    @State private var newSite = ""

    var body: some View {
        @Bindable var music = state.music
        @Bindable var keySounds = state.keySounds

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
                Text("Keyboard sounds")
                Picker("Keyboard sounds", selection: $keySounds.mode) {
                    ForEach(KeySoundMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if keySounds.needsPermission {
                    HStack(alignment: .firstTextBaseline) {
                        caption("Zone needs Input Monitoring permission to hear your keys.")
                        Spacer()
                        Button("Open Settings") { keySounds.openPermissionSettings() }
                    }
                }
                if keySounds.mode != .off {
                    row("Volume") {
                        Slider(value: $keySounds.volume, in: 0...1)
                            .frame(width: 150)
                    }
                    row("Pitch") {
                        Picker("Pitch", selection: $keySounds.pitchVariation) {
                            ForEach(KeySounds.pitchSteps, id: \.self) { Text($0.formatted()).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .help("Each keystroke is shifted up or down by up to this many semitones, so repeated keys sound natural.")
                    Text("Quiet in")
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(StoredList.items(quietApps), id: \.self) { id in
                            let info = AppBlocker.info(for: id)
                            BlockRow(name: info?.name ?? id, isOn: isOn(id, disabled: $disabledQuietApps),
                                     remove: { remove(id, from: $quietApps, disabled: $disabledQuietApps) }) {
                                if let icon = info?.icon {
                                    Image(nsImage: icon).resizable()
                                } else {
                                    Image(systemName: "app.dashed").foregroundStyle(palette.muted)
                                }
                            }
                        }
                        Button("Add App…") {
                            let ids = StoredList.items(quietApps)
                            quietApps = StoredList.string(ids + AppBlocker.pickApps(prompt: "Add").filter { !ids.contains($0) })
                        }
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                }
                caption("Switch clicks as you type, in any app. Always silent in password fields.")
            }

            card {
                Toggle("Block sites during sessions", isOn: $blockSites)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(StoredList.items(blockedSites), id: \.self) { site in
                        BlockRow(name: site, isOn: isOn(site, disabled: $disabledSites),
                                 remove: { remove(site, from: $blockedSites, disabled: $disabledSites) }) {
                            SiteIcon(site: SiteBlocker.normalize(site))
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("Add site, e.g. reddit.com", text: $newSite)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit(addSite)
                        Button("Add", action: addSite)
                            .disabled(SiteBlocker.normalize(newSite).isEmpty)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .disabled(!blockSites)
                .opacity(blockSites ? 1 : 0.5)
                caption("Works in Safari, Chrome, Arc, Brave, Edge and Vivaldi. macOS asks once per browser for permission.")
            }

            card {
                Toggle("Quit apps during sessions", isOn: $blockApps)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(StoredList.items(blockedApps), id: \.self) { id in
                        let info = AppBlocker.info(for: id)
                        BlockRow(name: info?.name ?? id, isOn: isOn(id, disabled: $disabledApps),
                                 remove: { remove(id, from: $blockedApps, disabled: $disabledApps) }) {
                            if let icon = info?.icon {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "app.dashed").foregroundStyle(palette.muted)
                            }
                        }
                    }
                    Button("Add App…") {
                        let ids = StoredList.items(blockedApps)
                        blockedApps = StoredList.string(ids + AppBlocker.pickApps().filter { !ids.contains($0) })
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
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
                caption("Zone plays its own songs plus the ones in this folder.")
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onExitCommand(perform: onBack)
        .onAppear { state.keySounds.refresh() }
        .onChange(of: theme) { _, mode in mode.apply() }
    }

    private func addSite() {
        let site = SiteBlocker.normalize(newSite)
        let sites = StoredList.items(blockedSites)
        guard !site.isEmpty else { return }
        if !sites.map(SiteBlocker.normalize).contains(site) {
            blockedSites = StoredList.string(sites + [site])
        }
        newSite = ""
    }

    /// Switch state of one list item: on unless listed in `disabled`.
    private func isOn(_ item: String, disabled: Binding<String>) -> Binding<Bool> {
        Binding(
            get: { !StoredList.items(disabled.wrappedValue).contains(item) },
            set: { on in
                let others = StoredList.items(disabled.wrappedValue).filter { $0 != item }
                disabled.wrappedValue = StoredList.string(on ? others : others + [item])
            }
        )
    }

    private func remove(_ item: String, from list: Binding<String>, disabled: Binding<String>) {
        list.wrappedValue = StoredList.string(StoredList.items(list.wrappedValue).filter { $0 != item })
        disabled.wrappedValue = StoredList.string(StoredList.items(disabled.wrappedValue).filter { $0 != item })
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

/// One site or app in a block list: icon, name, a switch to pause it, and a remove button.
/// Clicking the icon or name flips the switch too.
private struct BlockRow<Icon: View>: View {
    let name: String
    @Binding var isOn: Bool
    let remove: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 18, height: 18)
                    .saturation(isOn ? 1 : 0)
                    .opacity(isOn ? 1 : 0.45)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isOn ? palette.text : palette.muted)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { PillSwitch.flip($isOn) }
            PillSwitch(label: name, isOn: $isOn)
            IconButton(systemName: "xmark", size: 10, help: "Remove", action: remove)
        }
    }
}

/// Compact switch in the app's palette: accent track when on, raised track when off.
private struct PillSwitch: View {
    let label: String
    @Binding var isOn: Bool

    @Environment(\.palette) private var palette

    static func flip(_ isOn: Binding<Bool>) {
        withAnimation(.spring(duration: 0.25, bounce: 0.25)) { isOn.wrappedValue.toggle() }
    }

    var body: some View {
        Button { Self.flip($isOn) } label: {
            Capsule()
                .fill(isOn ? palette.accent : palette.raised)
                .frame(width: 28, height: 16)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Pause" : "Resume")
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// Site favicon, or a globe until it loads (or if the site has none).
private struct SiteIcon: View {
    let site: String

    @Environment(\.palette) private var palette
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? Favicon.cached(site) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "globe").foregroundStyle(palette.muted)
            }
        }
        .task(id: site) { image = await Favicon.load(site) }
    }
}
