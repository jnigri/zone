import AVFoundation

enum MusicLibrary {
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff"]

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Music/Zone", directoryHint: .isDirectory)
    }

    /// The chosen folder, resolved from its bookmark so it survives renames/moves.
    /// Falls back to ~/Music/Zone, created on first use as a place to drop your own songs.
    static func folder() -> URL {
        if let data = UserDefaults.standard.data(forKey: Keys.folderBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                if stale { save(url) }
                return url
            }
        }
        let url = defaultFolder
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Songs shipped in Zone.app/Contents/Resources/Music, played straight from the app so
    /// every update brings its new songs along.
    static var bundledTracks: [URL] {
        guard let bundled = Bundle.main.resourceURL?.appending(path: "Music", directoryHint: .isDirectory) else { return [] }
        return tracks(in: bundled)
    }

    /// Everything Zone can play: the bundled songs plus the ones in `folder`. A folder song
    /// with the same mood and file name as a bundled one replaces it.
    static func library(folder: URL) -> [URL] {
        let own = tracks(in: folder)
        let ownKeys = Set(own.map(key))
        return (bundledTracks.filter { !ownKeys.contains(key($0)) } + own)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func key(_ url: URL) -> String {
        "\(SongInfo(url).mood.rawValue)/\(url.lastPathComponent)"
    }

    static func save(_ url: URL) {
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Keys.folderBookmark)
        }
    }

    /// Songs directly in `folder` plus those one level down in its mood folders
    /// ("Cruise", "Beast Mode").
    static func tracks(in folder: URL) -> [URL] {
        let contents = files(in: folder)
        let moodFolders = contents.filter { Mood(named: $0.lastPathComponent) != nil && isDirectory($0) }
        return (contents + moodFolders.flatMap { files(in: $0) })
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Matched by raw identifier: the .iTunesMetadataGrouping lookup misses it in these files.
    private static let groupingIdentifiers: Set<String> = ["itsk/%A9grp", "id3/TIT1"]

    /// Comma-separated words in the song's Grouping field (Music app, Get Info), lowercased.
    static func tags(for url: URL) async -> [String] {
        guard let items = try? await AVURLAsset(url: url).load(.metadata),
              let grouping = items.first(where: { groupingIdentifiers.contains($0.identifier?.rawValue ?? "") }),
              let value = try? await grouping.load(.stringValue)
        else { return [] }
        var seen = Set<String>()
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
