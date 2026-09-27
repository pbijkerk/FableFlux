import SwiftUI

/// Compacte, neutrale fact-check-waarschuwing per onderwerp-cluster (R7).
/// Verschijnt alleen als het cluster minstens één artikel met een betwijfeld
/// verdict bevat (deterministisch geclassificeerd, geen AI). Nooit de app's eigen
/// stem — spreekt via de beoordelaar(s): "Bevat een betwijfelde bewering — …".
///
/// - `compact`: platte inline-regel voor de onderwerp-rij (`SummaryListView`).
///   Standaard toont een inklapbare kaart voor de detailheader.
struct FactCheckWarningView: View {
    let results: [FactCheckResult]
    var compact = false

    @State private var isExpanded = false

    @AppStorage(AppConfiguration.UserDefaultsKeys.analysisTextSize)
    private var analysisTextSize = AppConfiguration.defaultAnalysisTextSize

    /// Schaalt mee met Dynamic Type; verhouding met de gebruikersinstelling blijft behouden.
    @ScaledMetric(relativeTo: .caption) private var scaledBase: CGFloat = 12

    private var base: CGFloat { scaledBase * CGFloat(analysisTextSize) / 12 }

    private var raterSummary: String {
        var seen = Set<String>()
        let unique = results.map { $0.rater }.filter { seen.insert($0).inserted }
        return unique.count == 1 ? unique[0] : "\(unique.count) beoordelaars"
    }

    var body: some View {
        if !results.isEmpty {
            if compact {
                compactLabel
            } else {
                expandableCard
            }
        }
    }

    // MARK: - Compacte inline-regel (onderwerp-rij)

    private var compactLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: max(base - 2, 9)))
            Text("Bevat een betwijfelde bewering")
                .font(.system(size: max(base - 2, 9), weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.accentSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bevat een betwijfelde bewering, beoordeeld door \(raterSummary)")
    }

    // MARK: - Inklapbare kaart (detailheader)

    private var expandableCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: base))
                        .foregroundStyle(Theme.accentSecondary)
                    Text("Bevat een betwijfelde bewering — beoordeeld door \(raterSummary)")
                        .font(.system(size: base, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: max(base - 2, 8)))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\"\(result.claim)\"")
                                .font(.system(size: base))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            HStack(spacing: 4) {
                                Text("Beoordeeld als")
                                    .font(.system(size: base))
                                    .foregroundStyle(.secondary)
                                Text(result.verdict)
                                    .font(.system(size: base, weight: .semibold))
                                    .foregroundStyle(Theme.accentSecondary)
                                Text("door \(result.rater)")
                                    .font(.system(size: base))
                                    .foregroundStyle(.tertiary)
                            }

                            if let urlStr = result.resultURL, let url = URL(string: urlStr) {
                                Link("Bekijk beoordeling →", destination: url)
                                    .font(.system(size: base))
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.accentSecondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accentSecondary.opacity(0.18), lineWidth: 0.5)
        )
    }
}
