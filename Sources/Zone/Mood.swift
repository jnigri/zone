import Foundation

/// The phases of a work day a listener picks music for. A song belongs to a mood through its
/// file name: "mood.genre.title", e.g. "beast_mode.lofi.heavy_lifting.m4a".
enum Mood: String, CaseIterable, Identifiable {
    case bootUp, cruise, noExcuses, recharge, beastMode, ultraFocus, nightOwl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bootUp: "Boot Up"
        case .cruise: "Cruise"
        case .noExcuses: "No Excuses"
        case .recharge: "Recharge"
        case .beastMode: "Beast Mode"
        case .ultraFocus: "Ultra Focus"
        case .nightOwl: "Night Owl"
        }
    }

    var subtitle: String {
        switch self {
        case .bootUp: "Ease into the day"
        case .cruise: "Steady pace for routine work"
        case .noExcuses: "Stop stalling, get started"
        case .recharge: "Take a breather"
        case .beastMode: "Home stretch, full power"
        case .ultraFocus: "Thinking hard, zero distraction"
        case .nightOwl: "Stay awake, easy on the ears"
        }
    }

    var symbol: String {
        switch self {
        case .bootUp: "sunrise"
        case .cruise: "sailboat"
        case .noExcuses: "bolt"
        case .recharge: "cup.and.saucer"
        case .beastMode: "flame"
        case .ultraFocus: "scope"
        case .nightOwl: "moon.stars"
        }
    }

    /// Matches a file name prefix however it is spelled: "boot_up", "bootup" and "Boot Up" are the same mood.
    init?(named text: String) {
        let key = Self.key(text)
        guard let mood = Self.allCases.first(where: { Self.key($0.title) == key }) else { return nil }
        self = mood
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter(\.isLetter)
    }
}

/// What a song's file name says about it. Files not named "mood.genre.title" have no mood or
/// genre and only play when no mood is picked.
struct SongInfo {
    let mood: Mood?
    /// Lowercase, e.g. "lofi".
    let genre: String?
    let title: String

    init(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: ".", maxSplits: 2).map(Self.words)
        if parts.count == 3, let mood = Mood(named: parts[0]), !parts[1].isEmpty, !parts[2].isEmpty {
            self.mood = mood
            genre = parts[1].lowercased()
            title = parts[2].capitalized
        } else {
            mood = nil
            genre = nil
            title = name
        }
    }

    private static func words(_ part: Substring) -> String {
        part.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
