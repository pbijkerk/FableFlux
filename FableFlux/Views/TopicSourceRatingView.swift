import SwiftUI

/// Tweeassige bronduiding per onderwerp-cluster (R4): een politieke-kleurspectrum met
/// afgeleid "overwegend"-label plus een afgeleid betrouwbaarheidslabel, geaggregeerd
/// over de distinct bronnen van het cluster. Hergebruikt de bestaande `BiasSpectrumStrip`
/// en `ReliabilityBadgeView`. Positie is primair, kleur secundair.
///
/// Assen zonder enkele bekende rating worden verborgen — er wordt nooit een
/// centrum/high-waarde geraden. Zonder beide assen rendert de view niets.
struct TopicSourceRatingView: View {
    let cluster: TopicCluster

    private var biasScores: [Int] { cluster.sourceBiasScores }
    private var reliability: String? { cluster.dominantReliability }

    var body: some View {
        if !biasScores.isEmpty || reliability != nil {
            VStack(alignment: .leading, spacing: 4) {
                if !biasScores.isEmpty {
                    HStack(spacing: 8) {
                        BiasSpectrumStrip(biasScores: biasScores)
                        if let label = cluster.dominantBiasLabel {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if reliability != nil {
                    ReliabilityBadgeView(level: reliability)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
