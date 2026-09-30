import Foundation

/// Parses loose human durations: "30", "12m", "39min", "120s", "12 secs",
/// "1h", "1h 40m", "1h40", "1.5h", "2 hours and 5 minutes".
/// A bare number means minutes; a bare number after hours means minutes too.
/// "∞", "inf" or "infinite" mean an open-ended session.
enum DurationParser {
    static let maximum: TimeInterval = 24 * 3600

    private static let token = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*([a-z]*)"#)

    static func parse(_ input: String) -> TimeInterval? {
        let text = input.lowercased().trimmingCharacters(in: .whitespaces)
        if ["∞", "inf", "infinite", "infinity"].contains(text) { return .infinity }
        let range = NSRange(text.startIndex..., in: text)
        let matches = token.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        // Anything left between tokens must be filler, otherwise reject ("1h xyz").
        let leftover = token.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "and", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,+"))
        guard leftover.isEmpty else { return nil }

        var total: TimeInterval = 0
        for match in matches {
            let number = String(text[Range(match.range(at: 1), in: text)!]).replacingOccurrences(of: ",", with: ".")
            let unit = String(text[Range(match.range(at: 2), in: text)!])
            guard let value = Double(number), let seconds = seconds(per: unit) else { return nil }
            total += value * seconds
        }
        let rounded = total.rounded()
        return rounded > 0 && rounded <= maximum ? rounded : nil
    }

    private static func seconds(per unit: String) -> TimeInterval? {
        switch unit {
        case "h", "hr", "hrs", "hour", "hours": 3600
        case "", "m", "mn", "min", "mins", "minute", "minutes": 60
        case "s", "sec", "secs", "second", "seconds": 1
        default: nil
        }
    }
}
