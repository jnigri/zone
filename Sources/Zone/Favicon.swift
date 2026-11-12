import AppKit

/// Site icons for the block list, fetched straight from each site rather than a third-party
/// favicon service, so the block list never leaves the Mac beyond a plain request to that site.
/// Kept in memory for the app's lifetime; URLSession's disk cache covers relaunches.
@MainActor
enum Favicon {
    private static var cache: [String: NSImage] = [:]
    private static var misses: Set<String> = []

    static func cached(_ site: String) -> NSImage? { cache[site] }

    /// Large touch icon first (sharp on Retina), then the classic favicon.ico.
    static func load(_ site: String) async -> NSImage? {
        if let image = cache[site] { return image }
        guard !site.isEmpty, !misses.contains(site) else { return nil }
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(site)/\(path)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.isValid
            else { continue }
            cache[site] = image
            return image
        }
        misses.insert(site)
        return nil
    }
}
