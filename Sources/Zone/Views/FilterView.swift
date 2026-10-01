import SwiftUI

/// Tag filter shown in place of the session view: every tag found in the music folder,
/// on by default; switching one off skips the songs that have it.
struct FilterView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let music = state.music
        let tags = music.allTags

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "Back") { onBack() }
                Text("Filter")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            .padding(.leading, -8)

            if tags.isEmpty {
                card {
                    Text("No tags yet.")
                    caption("Add tags to your songs with Zone Admin, then come back here to skip the ones you don't want right now.")
                }
            } else {
                card {
                    caption("Turn a tag off to skip songs that have it. Untagged songs always play.")
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.tag) { item in
                            TagToggle(
                                tag: item.tag,
                                count: item.count,
                                isOn: !music.skippedTags.contains(item.tag)
                            ) { music.setTag(item.tag, enabled: $0) }
                        }
                    }
                }

                HStack {
                    Text("\(music.playableTracks.count) of \(music.tracks.count) songs will play")
                        .font(.callout)
                        .foregroundStyle(palette.muted)
                    Spacer()
                    if !music.skippedTags.isEmpty {
                        Button("Turn all on") { music.enableAllTags() }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(palette.link)
                    }
                }
            }
        }
        .onExitCommand(perform: onBack)
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

private struct TagToggle: View {
    let tag: String
    let count: Int
    let isOn: Bool
    let onToggle: (Bool) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            onToggle(!isOn)
        } label: {
            HStack(spacing: 5) {
                Text(tag)
                    .strikethrough(!isOn, color: palette.muted)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.muted)
            }
            .font(.system(.callout, design: .rounded, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? palette.raised : palette.background, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? palette.accent.opacity(0.6) : palette.raised, lineWidth: 1))
            .foregroundStyle(isOn ? palette.text : palette.muted)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Playing songs tagged “\(tag)”, click to skip them" : "Skipping songs tagged “\(tag)”, click to play them")
    }
}
