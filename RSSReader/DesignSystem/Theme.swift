import SwiftUI

// MARK: - Hex helpers

extension UIColor {
    /// Maakt een UIColor van een 24-bits hex-waarde (bijv. 0xFF9500).
    convenience init(hex: UInt) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// Dynamische kleur die automatisch wisselt tussen light- en dark-mode.
    init(light: UInt, dark: UInt) {
        self = Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            })
    }
}

// MARK: - Retro Future thema

/// Centrale kleur- en typografie-definities voor het "Retro Future"-ontwerp.
/// Warme tinten, tijdschrift-gevoel, zacht voor de ogen.
enum Theme {

    // MARK: Kleuren (light / dark)

    /// Rich Amber → Neon Amber. Semantische kleur voor "gemengd"/waarschuwing; volgt het thema
    /// bewust niet. De accentkleur van de app komt uit `AppTheme` via de `.tint`-stijl.
    static let amber = Color(light: 0xFF9500, dark: 0xFFB340)

    /// Deep Raspberry → Vivid Pink. Secundair accent: opvallend voor notificaties.
    static let accentSecondary = Color(light: 0xD12D55, dark: 0xFF375F)

    /// Cream Sand → Velvet Night. Hoofdachtergrond.
    static let background = Color(light: 0xF4F3EF, dark: 0x121214)

    /// Alabaster → Onyx. Kaart-oppervlak met subtiel diepte-effect.
    static let card = Color(light: 0xFDFDFB, dark: 0x1E1E22)

    /// Primaire tekst — semantisch, optimaal contrast in beide modi.
    static let text = Color.primary

    /// Secundaire tekst (metadata, datums).
    static let textSecondary = Color.secondary

    // MARK: Maatvoering

    /// Hoekradius voor kaarten (iOS-magazine-look).
    static let cardCornerRadius: CGFloat = 22

    // MARK: Typografie

    /// Kop in Charter Black (ingebouwd iOS serif-lettertype, krachtige schreven).
    /// Schaalt mee met Dynamic Type via `relativeTo`.
    static func headline(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("Charter-Black", size: size, relativeTo: style)
    }

    /// Subkop / titel in Charter Bold.
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
        .custom("Charter-Bold", size: size, relativeTo: style)
    }

    /// Categorie-/bron-label: klein, vet, hoofdletters — in de accentkleur van de bron.
    static func categoryLabel(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    // MARK: - Brand color per feed

    /// Warme accentkleuren-palet dat past bij het Retro Future-thema.
    private static let brandPalette: [Color] = [
        Color(light: 0xFF9500, dark: 0xFFB340),  // Amber
        Color(light: 0xD12D55, dark: 0xFF375F),  // Raspberry
        Color(light: 0xFF6B35, dark: 0xFF8C5A),  // Terracotta
        Color(light: 0xC9A227, dark: 0xE8C547),  // Gold
        Color(light: 0xB5651D, dark: 0xD98E4A),  // Rust
        Color(light: 0x9B2D5E, dark: 0xCD5C8A),  // Plum
        Color(light: 0xE07856, dark: 0xF0967A),  // Coral
        Color(light: 0x7A8450, dark: 0xA3B072),  // Olive
    ]

    /// Geeft een stabiele, deterministische accentkleur voor een bron.
    /// Dezelfde sleutel (feed-titel of -URL) levert altijd dezelfde kleur.
    static func brandColor(for key: String) -> Color {
        guard !key.isEmpty else { return amber }
        // Stabiele hash (djb2) — onafhankelijk van Swift's per-run hashSeed.
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return brandPalette[Int(hash % UInt64(brandPalette.count))]
    }
}
