import SwiftUI

/// Horizontale 5-positie balk (L · lL · C · lR · R) die de politieke positie van een nieuwsbron toont.
/// Positie is de primaire indicator; kleur is secundair voor kleurenblinden.
/// Tikken opent een transparantie-sheet met toelichting.
struct BiasBarView: View {
    let biasScore: Int  // -2 … +2
    let feedName: String
    let reliabilityLevel: String?
    let ratingSource: String?
    let biasRatedAt: Date?

    @State private var showTransparency = false

    @AppStorage(AppConfiguration.UserDefaultsKeys.analysisTextSize)
    private var analysisTextSize = AppConfiguration.defaultAnalysisTextSize

    /// Schaalt mee met Dynamic Type; verhouding met de gebruikersinstelling blijft behouden.
    @ScaledMetric(relativeTo: .caption) private var scaledBase: CGFloat = 12

    private var base: CGFloat { scaledBase * CGFloat(analysisTextSize) / 12 }
    private var labelSize: CGFloat { max(base - 3, 8) }
    private var selectedDot: CGFloat { max(base - 2, 9) }
    private var unselectedDot: CGFloat { selectedDot * 0.6 }

    private static let positions: [(score: Int, label: String)] = [
        (-2, "L"), (-1, "lL"), (0, "C"), (1, "lR"), (2, "R"),
    ]

    var body: some View {
        Button {
            showTransparency = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                ZStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: max(3, base * 0.25))

                    HStack(spacing: 0) {
                        ForEach(Self.positions, id: \.score) { pos in
                            Group {
                                if pos.score == biasScore {
                                    Circle()
                                        .fill(dotColor(pos.score))
                                        .frame(width: selectedDot, height: selectedDot)
                                } else {
                                    Circle()
                                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                                        .frame(width: unselectedDot, height: unselectedDot)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: selectedDot)

                HStack(spacing: 0) {
                    ForEach(Self.positions, id: \.score) { pos in
                        Text(pos.label)
                            .font(.system(size: labelSize, weight: pos.score == biasScore ? .semibold : .regular))
                            .foregroundStyle(pos.score == biasScore ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Politieke positie: \(biasLabel(biasScore)). Tik voor meer informatie.")
        .sheet(isPresented: $showTransparency) {
            TransparencySheetView(
                feedName: feedName,
                biasScore: biasScore,
                reliabilityLevel: reliabilityLevel,
                ratingSource: ratingSource,
                biasRatedAt: biasRatedAt
            )
        }
    }

    private func dotColor(_ score: Int) -> Color { biasColor(for: score) }
}

// MARK: - Helpers

/// Gedeelde kleur-mapping bias-score → Color (BiasBarView + TransparencySheetView).
func biasColor(for score: Int) -> Color {
    switch score {
    case -2: return Color(light: 0x2558A0, dark: 0x5B90D0)
    case -1: return Color(light: 0x5B8DB8, dark: 0x89B8E0)
    case 0: return Color(.systemGray3)
    case 1: return Theme.amber
    case 2: return Theme.accentSecondary
    default: return Color(.systemGray3)
    }
}

/// Gedeelde vertaling reliability-string → Nederlandse label (TransparencySheetView + ReliabilityBadgeView).
func reliabilityLabel(_ level: String) -> String {
    switch level.lowercased() {
    case "high": return "Hoog"
    case "mixed": return "Gemiddeld"
    case "low": return "Laag"
    default: return level
    }
}

func biasLabel(_ score: Int) -> String {
    switch score {
    case -2: return "Links"
    case -1: return "Licht links"
    case 0: return "Centrum"
    case 1: return "Licht rechts"
    case 2: return "Rechts"
    default: return "Onbekend"
    }
}

// MARK: - Transparency sheet

struct TransparencySheetView: View {
    let feedName: String
    let biasScore: Int
    let reliabilityLevel: String?
    let ratingSource: String?
    let biasRatedAt: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bron") {
                    LabeledContent("Feed", value: feedName)
                    HStack {
                        Text("Politieke positie")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(positionColor)
                                .frame(width: 8, height: 8)
                            Text(biasLabel(biasScore))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let rel = reliabilityLevel {
                        LabeledContent("Feitelijke betrouwbaarheid", value: reliabilityLocalised(rel))
                    }
                }

                if let sources = ratingSource, !sources.isEmpty {
                    Section("Beoordelaars") {
                        ForEach(sources.components(separatedBy: ", "), id: \.self) { rater in
                            Label(rater, systemImage: "checkmark.seal")
                        }
                        if let date = biasRatedAt {
                            LabeledContent("Bijgewerkt", value: date.formatted(.dateTime.day().month().year()))
                        }
                    }
                }

                Section {
                    Text(
                        "Deze beoordeling geldt voor de nieuwsbron als geheel, niet voor dit specifieke artikel. Politieke positie en betrouwbaarheid worden bepaald door onafhankelijke organisaties (AllSides, Media Bias/Fact Check e.a.) op basis van redactioneel beleid, brongebruik en externe audits."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Toelichting")
                }
            }
            .navigationTitle("Over deze bron")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") { dismiss() }
                }
            }
        }
    }

    private var positionColor: Color { biasColor(for: biasScore) }

    private func reliabilityLocalised(_ level: String) -> String { reliabilityLabel(level) }
}
