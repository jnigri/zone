import AppKit

/// Blocks distracting sites while a session runs: once a second, reads the front tab of the
/// frontmost browser over AppleScript and swaps blocked pages for a notice.
/// Only the frontmost app is queried, so Zone never launches a browser.
final class SiteBlocker {
    static let defaultSites = "youtube.com\nnetflix.com"

    /// Bundle identifier to the AppleScript reference of that browser's front tab.
    private static let browsers: [String: String] = [
        "com.apple.Safari": "current tab of front window",
        "com.google.Chrome": "active tab of front window",
        "company.thebrowser.Browser": "active tab of front window",
        "com.brave.Browser": "active tab of front window",
        "com.microsoft.edgemac": "active tab of front window",
        "com.vivaldi.Vivaldi": "active tab of front window",
    ]

    private var ticker: Timer?
    private var readScripts: [String: NSAppleScript] = [:]

    func update(active: Bool) {
        if active, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !active {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.blockSites) as? Bool ?? true
    }

    private var blockedSites: [String] {
        StoredList.enabled(Keys.blockedSites, default: Self.defaultSites, disabledKey: Keys.disabledSites)
            .map(Self.normalize)
            .filter { !$0.isEmpty }
    }

    private func check() {
        guard isEnabled,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let tab = Self.browsers[id],
              let host = currentURL(browser: id, tab: tab)?.host().map(Self.normalize),
              let site = blockedSites.first(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return }
        run("tell application id \"\(id)\" to set URL of \(tab) to \"\(Self.blockPage(site))\"")
    }

    private func currentURL(browser id: String, tab: String) -> URL? {
        let script = readScripts[id] ?? NSAppleScript(source: "tell application id \"\(id)\" to get URL of \(tab)")
        readScripts[id] = script
        var error: NSDictionary?
        guard let value = script?.executeAndReturnError(&error).stringValue else { return nil }
        return URL(string: value)
    }

    private func run(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// "https://www.YouTube.com/" or "www.youtube.com" → "youtube.com".
    static func normalize(_ site: String) -> String {
        var s = site.trimmingCharacters(in: .whitespaces).lowercased()
        if let host = URL(string: s)?.host() { s = host }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }

    /// Notice page shown in place of a blocked site, as a data URL (no files needed).
    private static func blockPage(_ site: String) -> String {
        let html = """
        <!doctype html><meta charset="utf-8"><title>Blocked by Zone</title>
        <style>
        body{margin:0;height:100vh;display:grid;place-items:center;font:16px -apple-system,system-ui,sans-serif;
        background:#f6f5f2;color:#1d1d1f;text-align:center}
        @media (prefers-color-scheme:dark){body{background:#161618;color:#ececec}}
        h1{font:600 28px ui-rounded,-apple-system,sans-serif;margin:0 0 8px}p{opacity:.6;margin:0}
        </style>
        <div><h1>Stay in the zone</h1><p>\(site) is blocked until your session ends.</p></div>
        """
        return "data:text/html;charset=utf-8," + (html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    }
}
