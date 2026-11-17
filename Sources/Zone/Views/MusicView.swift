import SwiftUI

/// Shown in place of the session view: one row per tag on the current mood's songs, each with
/// Only and Exclude buttons, and the disliked songs with a way to bring them back.
struct MusicView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let music = state.music
        let tags = music.allTags
        let disliked = music.dislikedTracks

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "Back") { onBack() }
                Text("Music")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Reset") { music.clearTags() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(music.isFiltering ? palette.link : palette.muted.opacity(0.5))
                    .disabled(!music.isFiltering)
                    .help("Turn off every Only and Exclude")
                IconButton(systemName: "arrow.clockwise", help: "Rescan folder for songs and tags") {
                    state.rescanFolder()
                }
            }
            .padding(.leading, -8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tags.isEmpty {
                        card {
                            Text("No tags yet.")
                            caption("Add comma-separated tags to your songs' Grouping field (Music app, Get Info), then press refresh to pick what you want to hear right now.")
                        }
                    } else {
                        card {
                            summary(music)
                            VStack(spacing: 6) {
                                ForEach(tags, id: \.tag) { item in
                                    TagRow(tag: item.tag, count: item.count, mode: music.mode(for: item.tag)) {
                                        music.setTag(item.tag, mode: $0)
                                    }
                                }
                            }
                        }
                    }

                    if !disliked.isEmpty {
                        card {
                            caption("Songs you marked as disliked never play. Restore one to put it back in rotation.")
                            ForEach(disliked, id: \.self) { url in
                                HStack(spacing: 6) {
                                    Text(music.title(for: url))
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Restore") { music.restore(url) }
                                        .buttonStyle(.plain)
                                        .font(.callout)
                                        .foregroundStyle(palette.link)
                                }
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onExitCommand(perform: onBack)
    }

    /// "Playing 7 of 13 Cruise songs" plus, in words, what the Only and Exclude buttons add up to.
    private func summary(_ music: MusicPlayer) -> some View {
        let playing = music.playableTracks.count
        let only = music.includedTags.sorted()
        let exclude = music.excludedTags.sorted()
        var rules: [String] = []
        if !only.isEmpty { rules.append("only " + Self.list(only, joiner: "or")) }
        if !exclude.isEmpty { rules.append("excluding " + Self.list(exclude, joiner: "and")) }
        let joined = rules.joined(separator: ", ")
        let detail = playing == 0
            ? "No song matches. Turn off an Only or Exclude, or press Reset."
            : rules.isEmpty
                ? "Every song plays. Press Only to hear just a tag, Exclude to leave it out."
                : joined.prefix(1).uppercased() + joined.dropFirst() + "."
        return VStack(alignment: .leading, spacing: 2) {
            Text("Playing \(playing) of \(music.moodTracks.count) \(music.mood.title) songs")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(playing == 0 ? palette.wrong : palette.text)
            caption(detail)
        }
    }

    /// ["calm", "guitar", "jazz"] → "calm, guitar or jazz".
    private static func list(_ items: [String], joiner: String) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " \(joiner) " + items.last!
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One tag per line: name and song count, with Only and Exclude buttons. Neither pressed means
/// the tag doesn't matter; pressing the lit one turns it off again.
private struct TagRow: View {
    let tag: String
    let count: Int
    let mode: TagMode
    let onChange: (TagMode) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(mode == .exclude ? palette.muted : palette.text)
                .strikethrough(mode == .exclude, color: palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.muted)
            Spacer(minLength: 4)
            choice("Only", .include, color: palette.accent,
                   help: "Play only songs tagged “\(tag)” (or another Only tag)")
            choice("Exclude", .exclude, color: palette.wrong,
                   help: "Never play songs tagged “\(tag)”")
        }
    }

    private func choice(_ title: String, _ value: TagMode, color: Color, help: String) -> some View {
        let isOn = mode == value
        return Button {
            onChange(isOn ? .normal : value)
        } label: {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .frame(minWidth: 30)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? color : palette.background, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : palette.raised, lineWidth: 1))
                .foregroundStyle(isOn ? .white : palette.muted)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Click to turn off" : help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
