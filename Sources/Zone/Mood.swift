import Foundation

/// How hard a listener wants to push. A song belongs to a mood through the folder it sits in,
/// e.g. "Beast Mode/Heavy Lifting.m4a".
enum Mood: String, CaseIterable, Identifiable {
    case cruise, beastMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cruise: "Cruise"
        case .beastMode: "Beast Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .cruise: "Steady pace for routine work"
        case .beastMode: "Full power, no holding back"
        }
    }

    var symbol: String {
        switch self {
        case .cruise: "sailboat"
        case .beastMode: "flame"
        }
    }

    /// Matches a folder name however it is spelled: "Beast Mode", "beast_mode" and "beastmode"
    /// are the same mood.
    init?(named text: String) {
        let key = Self.key(text)
        guard let mood = Self.allCases.first(where: { Self.key($0.title) == key }) else { return nil }
        self = mood
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter(\.isLetter)
    }
}

/// What a song's location says about it. The folder it sits in names its mood ("Cruise",
/// "Beast Mode"); songs anywhere else play in Cruise. The file name is the title.
struct SongInfo {
    let mood: Mood
    let title: String

    init(_ url: URL) {
        mood = Mood(named: url.deletingLastPathComponent().lastPathComponent) ?? .cruise
        title = url.deletingPathExtension().lastPathComponent
    }
}
