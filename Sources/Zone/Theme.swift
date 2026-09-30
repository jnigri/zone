import AppKit
import SwiftUI

struct Palette {
    let background: Color
    let panel: Color
    let raised: Color
    let text: Color
    let muted: Color
    let accent: Color
    let link: Color
    let correct: Color
    let wrong: Color

    static let dark = Palette(
        background: Color(hex: 0x141516),
        panel: Color(hex: 0x1D1F20),
        raised: Color(hex: 0x2C2F31),
        text: Color(hex: 0xE6E8E9),
        muted: Color(hex: 0x8A8F93),
        accent: Color(hex: 0xFF5A00),
        link: Color(hex: 0xFF8A3D),
        correct: Color(hex: 0x5FCF7D),
        wrong: Color(hex: 0xFF4D6A)
    )

    static let light = Palette(
        background: Color(hex: 0xEEF0F1),
        panel: Color(hex: 0xE1E4E6),
        raised: Color(hex: 0xCCD1D4),
        text: Color(hex: 0x161616),
        muted: Color(hex: 0x6C7176),
        accent: Color(hex: 0xE85400),
        link: Color(hex: 0xB33A00),
        correct: Color(hex: 0x23803F),
        wrong: Color(hex: 0xC8102E)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    /// Applied app-wide through NSApp.appearance so every window, including the
    /// menu bar panel, follows the choice (preferredColorScheme(nil) does not revert reliably).
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    static var stored: ThemeMode {
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "") ?? .system
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

private struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = scheme == .dark ? Palette.dark : Palette.light
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}
