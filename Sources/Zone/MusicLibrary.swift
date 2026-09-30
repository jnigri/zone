import Foundation

enum MusicLibrary {
    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff"]

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Music/Zone", directoryHint: .isDirectory)
    }

    /// The chosen folder, resolved from its bookmark so it survives renames/moves.
    /// Falls back to ~/Music/Zone, created on first use.
    static func folder() -> URL {
        if let data = UserDefaults.standard.data(forKey: Keys.folderBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                if stale { save(url) }
                return url
            }
        }
        let url = defaultFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
