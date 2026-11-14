import Foundation

/// UserDefaults keys shared by @AppStorage and model code.
enum Keys {
    static let showInMenuBar = "showInMenuBar"
    static let theme = "theme"
    static let volume = "volume"
    static let muted = "muted"
    static let duration = "duration"
    static let folderBookmark = "folderBookmark"
    static let focusModulation = "focusModulation"
    static let modulationDepth = "modulationDepth"
    static let mood = "mood"
    static let genre = "genre"
    static let dislikedSongs = "dislikedSongs"
    static let blockSites = "blockSites"
    static let blockedSites = "blockedSites"
    static let blockApps = "blockApps"
    static let blockedApps = "blockedApps"
    static let disabledSites = "disabledSites"
    static let disabledApps = "disabledApps"
    static let keepAwake = "keepAwake"
    static let keySounds = "keySounds"
    static let keySoundVolume = "keySoundVolume"
    static let keySoundPitch = "keySoundPitch"
    static let quietApps = "quietApps"
    static let disabledQuietApps = "disabledQuietApps"
}

/// Settings lists (sites, apps) are stored as one item per line.
enum StoredList {
    static func items(_ stored: String) -> [String] {
        stored.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func string(_ items: [String]) -> String {
        items.joined(separator: "\n")
    }

    /// Items of `key` that are switched on: listed and not in `disabledKey`.
    static func enabled(_ key: String, default fallback: String, disabledKey: String) -> [String] {
        let defaults = UserDefaults.standard
        let disabled = Set(items(defaults.string(forKey: disabledKey) ?? ""))
        return items(defaults.string(forKey: key) ?? fallback).filter { !disabled.contains($0) }
    }
}
