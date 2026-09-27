import SwiftUI

/// Schild-badge met één woord die de factual reliability van een nieuwsbron toont.
/// Opzettelijk gescheiden van de bias-balk: bias en nauwkeurigheid zijn verschillende dimensies.
struct ReliabilityBadgeView: View {
    let level: String?  // "high", "mixed", "low" of nil

    @AppStorage(AppConfiguration.UserDefaultsKeys.analysisTextSize)
    private var analysisTextSize = AppConfiguration.defaultAnalysisTextSize

    /// Schaalt mee met Dynamic Type; verhouding met de gebruikersinstelling blijft behouden.
    @ScaledMetric(relativeTo: .caption) private var scaledBase: CGFloat = 12

    private var base: CGFloat { scaledBase * CGFloat(analysisTextSize) / 12 }

    var body: some View {
        if let level {
            HStack(spacing: 3) {
                Image(systemName: "shield.fill")
                    .font(.system(size: max(base - 3, 8)))
                    .foregroundStyle(shieldColor(level))
                Text(localised(level))
                    .font(.system(size: max(base - 2, 9), weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .accessibilityLabel("Betrouwbaarheid: \(localised(level))")
        }
    }

    private func shieldColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "high": return .green
        case "mixed": return Theme.amber
        case "low": return Theme.accentSecondary
        default: return .secondary
        }
    }

    private func localised(_ level: String) -> String { reliabilityLabel(level) }
}
