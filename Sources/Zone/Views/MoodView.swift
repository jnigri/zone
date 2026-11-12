import SwiftUI

/// Music picker shown in place of the session view: one mood to play, optionally narrowed to
/// one genre, plus the disliked songs with a way to bring them back.
struct MoodView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        let music = state.music

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "Back") { onBack() }
                Text("Music")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                IconButton(systemName: "arrow.clockwise", help: "Rescan folder for songs") {
                    state.rescanFolder()
                }
            }
            .padding(.leading, -8)

            VStack(spacing: 2) {
                MoodRow(
                    symbol: "shuffle", title: "Any Mood", subtitle: "Every song, yours included",
                    count: music.songCount(for: nil), selected: music.mood == nil
                ) { music.setMood(nil) }
                ForEach(Mood.allCases) { mood in
                    MoodRow(
                        symbol: mood.symbol, title: mood.title, subtitle: mood.subtitle,
                        count: music.songCount(for: mood), selected: music.mood == mood
                    ) { music.setMood(mood) }
                }
            }

            let genres = music.genres
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Genre")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            GenreChip(title: "All", selected: music.genre == nil) { music.setGenre(nil) }
                            ForEach(genres, id: \.self) { genre in
                                GenreChip(title: genre.capitalized, selected: music.genre == genre) {
                                    music.setGenre(genre)
                                }
                            }
                        }
                    }
                }
            }

            let disliked = music.dislikedTracks
            if !disliked.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Disliked")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These never play. Restore one to put it back in rotation.")
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
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
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .onExitCommand(perform: onBack)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(palette.muted)
    }
}

/// One mood per line: icon, name, what it is for and how many songs it has. Moods without
/// songs are dimmed but still selectable, so the main screen can explain what is missing.
private struct MoodRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.muted)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selected ? palette.raised : hovering ? palette.panel : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(count == 0 && !selected ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(count == 0 ? "No songs for this mood yet" : subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct GenreChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? palette.raised : palette.panel, in: Capsule())
                .foregroundStyle(selected ? palette.text : palette.muted)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
