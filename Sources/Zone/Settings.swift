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
    static let skippedTags = "skippedTags"
    static let selectedTags = "selectedTags"
    static let excludedTags = "excludedTags"
    static let dislikedSongs = "dislikedSongs"
    static let blockSites = "blockSites"
    static let blockedSites = "blockedSites"
    static let blockApps = "blockApps"
    static let blockedApps = "blockedApps"
    static let keepAwake = "keepAwake"
}
