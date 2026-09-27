import SwiftUI

struct StoryGroupHeaderView: View {
    let cluster: EventCluster
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(cluster.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                HStack(spacing: 0) {
                    Label("\(cluster.items.count)", systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 10)
                    Label("\(cluster.feedCount)", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    BiasSpectrumStrip(biasScores: cluster.biasScores)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }
}

/// 5-positie spectrumregel: gevulde stip = positie aanwezig in de groep.
struct BiasSpectrumStrip: View {
    let biasScores: [Int]

    private static let positions: [(score: Int, label: String)] = [
        (-2, "L"), (-1, "lL"), (0, "C"), (1, "lR"), (2, "R"),
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Self.positions, id: \.score) { pos in
                let present = biasScores.contains(pos.score)
                VStack(spacing: 2) {
                    Circle()
                        .fill(present ? biasColor(for: pos.score) : Color.secondary.opacity(0.15))
                        .frame(width: present ? 9 : 6, height: present ? 9 : 6)
                    Text(pos.label)
                        .font(.system(size: 7))
                        .foregroundStyle(present ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.3))
                }
            }
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard !biasScores.isEmpty else { return "Geen bekende politieke posities" }
        let labels = biasScores.sorted().map { biasLabel($0) }
        return "Posities aanwezig: \(labels.joined(separator: ", "))"
    }
}
