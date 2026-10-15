import AppKit
import CoreText
import SwiftUI

// MARK: - Appearance preference

/// User-selectable appearance for the whole app; `auto` follows macOS.
/// Ported from BirdNion's `AppAppearance`.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, auto
    var id: String { rawValue }

    /// NSAppearance to force app-wide, or nil to follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .auto: return nil
        }
    }

    var title: String { rawValue.capitalized }

    @MainActor static func apply(_ raw: String) {
        NSApp.appearance = AppAppearance(rawValue: raw)?.nsAppearance
    }
}

// MARK: - Theme
//
// BNTrans palette — the BirdNion "Instrument" redesign tokens ported 1:1:
// paper/ink surfaces, hairline dividers instead of filled cards, one accent.
// Every token is a dynamic color resolving light/dark from the effective
// appearance, matching `BirdNion/Views/Theme.swift` (`VocabbyTheme`).
enum BTTheme {
    /// Dynamic color: `light` under aqua, `dark` under darkAqua.
    private static func dyn(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgbRed: CGFloat((isDark ? dark : light) >> 16 & 0xFF) / 255,
                           green: CGFloat((isDark ? dark : light) >> 8 & 0xFF) / 255,
                           blue: CGFloat((isDark ? dark : light) & 0xFF) / 255,
                           alpha: 1)
        })
    }

    // Surfaces — paper (light) / ink (dark). `card` == `background`: sections
    // are separated by hairline dividers, not filled rounded cards.
    static let background = dyn(0xFBFAF7, 0x17170F)
    static let card = dyn(0xFBFAF7, 0x17170F)
    static let group = dyn(0xF3F1EA, 0x1E1E16)
    static let selectedSurface = dyn(0xE9E6DC, 0x262620)
    static let hoverSurface = dyn(0xEDEAE0, 0x262620)

    // Text
    static let primary = dyn(0x16150F, 0xF2F0E8)
    static let secondary = dyn(0x4B4941, 0xC9C6BC)
    static let tertiary = dyn(0x6B6862, 0xA3A096)
    static let muted = dyn(0x7A776C, 0xA3A096)
    static let disabled = dyn(0xB0ADA3, 0x4A4A40)

    // Accent + semantic states
    static let accent = dyn(0x1F4FD8, 0x7EA2FF)
    static let warning = dyn(0x8F5F12, 0xE0A93F)
    static let warningSurface = dyn(0xF5EEDD, 0x2A2418)
    static let success = dyn(0x1F7A4C, 0x58C089)
    static let critical = dyn(0xB4402F, 0xE5716A)

    // Chrome
    static let border = dyn(0xDCD8CD, 0x33332B)
    /// Quiet divider between stacked sections.
    static let hairline = dyn(0xE2DFD6, 0x2A2A22)
    /// Stronger rule under headers (== `primary`).
    static let inkRule = dyn(0x16150F, 0xF2F0E8)
    /// Header/footer full-bleed rule — one step heavier than `hairline`.
    static let chromeRule = dyn(0xC9C5BA, 0x3F3F36)
}

// MARK: - Fonts

/// Bundled IBM Plex family names, registered at launch by
/// `BTFont.registerBundledFonts()`.
enum BTFontFamily {
    static let sans = "IBM Plex Sans"
    static let mono = "IBM Plex Mono"
}

extension Font {
    /// Body/label/UI text. Falls back to the system font if the bundled font
    /// failed to register.
    static func plexSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(BTFontFamily.sans, size: size).weight(weight)
    }

    /// Numerals, URLs, model names, uppercase mono labels.
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(BTFontFamily.mono, size: size).weight(weight)
    }
}

/// IBM Plex via bundled TTFs (same files as BirdNion). NSFont helpers for the
/// AppKit overlay; falls back to the system font if registration misses.
enum BTFont {
    private static let fontFileNames = [
        "IBMPlexSans-Regular", "IBMPlexSans-Medium", "IBMPlexSans-SemiBold",
        "IBMPlexSans-Bold", "IBMPlexMono-Regular", "IBMPlexMono-Medium",
        "IBMPlexMono-SemiBold",
    ]

    static func registerBundledFonts() {
        for name in fontFileNames {
            guard
                let url = Bundle.module.url(
                    forResource: name,
                    withExtension: "ttf",
                    subdirectory: "Resources/Fonts"
                ) ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            else { continue }
            var err: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        }
    }

    static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular)
        -> NSFont
    {
        let name: String
        switch weight {
        case .medium: name = "IBMPlexSans-Medm"
        case .semibold: name = "IBMPlexSans-SmBld"
        case .bold: name = "IBMPlexSans-Bold"
        default: name = "IBMPlexSans"
        }
        return NSFont(name: name, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular)
        -> NSFont
    {
        let name =
            weight == .medium
            ? "IBMPlexMono-Medm"
            : weight == .semibold ? "IBMPlexMono-SmBld" : "IBMPlexMono"
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(
            ofSize: size, weight: weight)
    }
}
