import AVFoundation

enum MusicLibrary {
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff"]

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Music/Zone", directoryHint: .isDirectory)
    }

    /// The chosen folder, resolved from its bookmark so it survives renames/moves.
    /// Falls back to ~/Music/Zone, created on first use and filled with the songs bundled in the app.
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
            copyBundledSongs(to: url)
        }
        return url
    }

    /// Starter songs shipped in Zone.app/Contents/Resources/Music. Only copied into a brand-new
    /// folder, so an existing library is never touched and deleted songs don't come back.
    private static func copyBundledSongs(to folder: URL) {
        guard let bundled = Bundle.main.resourceURL?.appending(path: "Music", directoryHint: .isDirectory) else { return }
        for song in tracks(in: bundled) {
            try? FileManager.default.copyItem(at: song, to: folder.appending(path: song.lastPathComponent))
        }
    }

    static func save(_ url: URL) {
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Keys.folderBookmark)
        }
    }

    static func tracks(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Grouping field as ffmpeg (used by Zone Admin) writes it: ©grp in MP4 files, TIT1 in MP3s.
    /// Matched by raw identifier: the .iTunesMetadataGrouping lookup misses it in these files.
    private static let groupingIdentifiers: Set<String> = ["itsk/%A9grp", "id3/TIT1"]

    /// Tags written by Zone Admin: comma-separated, lowercase words in the Grouping field.
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
}
