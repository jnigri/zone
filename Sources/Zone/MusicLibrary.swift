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
    /// with the same file name as a bundled one replaces it (older versions copied the bundled
    /// songs into the folder).
    static func library(folder: URL) -> [URL] {
        let own = tracks(in: folder)
        let ownNames = Set(own.map(\.lastPathComponent))
        return (bundledTracks.filter { !ownNames.contains($0.lastPathComponent) } + own)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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
}
