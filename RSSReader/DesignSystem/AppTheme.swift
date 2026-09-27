import SwiftUI
import UIKit

// MARK: - Thema's

/// Kleurvariant van het FableFlux-logo. Bepaalt het app-icoon én de accentkleur van de app.
/// De logokleuren horen gelijk te blijven aan `generate_icon.py`, dat de app-iconen tekent.
enum AppTheme: String, CaseIterable, Identifiable {
    case origineel, oceaan, nacht, kampvuur, inkt, woud, perkament

    static let standaard: AppTheme = .origineel

    var id: String { rawValue }

    /// Leest de opgeslagen keuze; een onbekende of ontbrekende waarde valt terug op de standaard.
    init(storedValue: String?) {
        self = storedValue.flatMap(AppTheme.init(rawValue:)) ?? .standaard
    }

    var naam: String {
        switch self {
        case .origineel: return "Origineel"
        case .oceaan: return "Oceaan"
        case .nacht: return "Nacht"
        case .kampvuur: return "Kampvuur"
        case .inkt: return "Inkt"
        case .woud: return "Woud"
        case .perkament: return "Perkament"
        }
    }

    /// Naam van de alternatieve icoonset in de asset catalog; `nil` = het primaire `AppIcon`.
    var iconName: String? {
        self == .origineel ? nil : "AppIcon-\(naam)"
    }

    /// Accentkleur in de app, met een lichtere tint voor dark mode.
    var accent: Color {
        switch self {
        case .origineel: return Color(light: 0x1E7BF0, dark: 0x4A9BFF)
        case .oceaan: return Color(light: 0x0D9488, dark: 0x2DD4BF)
        case .nacht: return Color(light: 0x7C3AED, dark: 0xA78BFA)
        case .kampvuur: return Color(light: 0xEA580C, dark: 0xFB923C)
        case .inkt: return Color(light: 0xDB2777, dark: 0xF472B6)
        case .woud: return Color(light: 0x059669, dark: 0x34D399)
        case .perkament: return Color(light: 0xD97706, dark: 0xFBBF24)
        }
    }

    /// Kleuren van het logo zelf: ring, donkerder segment en achtergrond.
    var logoKleuren: (ring: UInt, segment: UInt, achtergrond: UInt) {
        switch self {
        case .origineel: return (0x1E7BF0, 0x0B5CC4, 0x061539)
        case .oceaan: return (0x14B8A6, 0x0F766E, 0x042F2E)
        case .nacht: return (0x8B5CF6, 0x6D28D9, 0x1E1B4B)
        case .kampvuur: return (0xF97316, 0xC2410C, 0x1C1917)
        case .inkt: return (0xEC4899, 0xBE185D, 0x2A0A1F)
        case .woud: return (0x10B981, 0x047857, 0x022C22)
        case .perkament: return (0xF59E0B, 0xB45309, 0x0F172A)
        }
    }
}

// MARK: - Accentkleur toepassen

/// Zet de accentkleur van het gekozen thema als `.tint`. Views lezen die via de
/// `.tint`-stijl (`.foregroundStyle(.tint)`, `.fill(.tint)`), zodat een wissel direct overal zichtbaar is.
private struct AppThemeTint: ViewModifier {
    @AppStorage(AppConfiguration.UserDefaultsKeys.appTheme)
    private var storedTheme = AppTheme.standaard.rawValue

    func body(content: Content) -> some View {
        content.tint(AppTheme(storedValue: storedTheme).accent)
    }
}

extension View {
    func appThemeTint() -> some View {
        modifier(AppThemeTint())
    }
}

// MARK: - Logo

/// Het FableFlux-logo in SwiftUI, voor de themakiezer. Zelfde geometrie als `generate_icon.py`.
struct FableFluxLogo: View {
    let theme: AppTheme

    var body: some View {
        let kleuren = theme.logoKleuren
        Canvas { context, size in
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side * 0.30
            let inner = outer * 20 / 46
            let gap = outer * 5 / 46
            let background = Color(uiColor: UIColor(hex: kleuren.achtergrond))

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

            let ring = CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)
            context.fill(Path(ellipseIn: ring), with: .color(Color(uiColor: UIColor(hex: kleuren.ring))))

            var segment = Path()
            segment.move(to: c)
            segment.addArc(
                center: c, radius: outer, startAngle: .degrees(225), endAngle: .degrees(360), clockwise: false)
            segment.closeSubpath()
            context.fill(segment, with: .color(Color(uiColor: UIColor(hex: kleuren.segment))))

            let hole = CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)
            context.fill(Path(ellipseIn: hole), with: .color(background))

            let d = outer * 0.75
            var cuts = Path()
            cuts.move(to: CGPoint(x: c.x - d - gap, y: c.y - d - gap))
            cuts.addLine(to: CGPoint(x: c.x - inner * 0.6, y: c.y - inner * 0.6))
            cuts.move(to: CGPoint(x: c.x + inner * 0.6, y: c.y + inner * 0.6))
            cuts.addLine(to: CGPoint(x: c.x + d + gap, y: c.y + d + gap))
            context.stroke(cuts, with: .color(background), lineWidth: gap)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
