import SwiftUI

struct SummaryListView: View {
    @Binding var clusters: [TopicCluster]
    let isLoading: Bool
    var onRefresh: () async -> Void

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if clusters.isEmpty {
                    emptyView
                } else {
                    clusterList
                }
            }
            .background(Theme.background)
            .refreshable { await onRefresh() }
            .navigationTitle("Vandaag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Instellingen", systemImage: "gearshape") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Je feeds worden geanalyseerd…")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    /// In een ScrollView met altijd-bounce, zodat pull-to-refresh ook werkt
    /// wanneer er nog geen samenvattingen zijn.
    private var emptyView: some View {
        ScrollView {
            // Vult de hoogte van de ScrollView, zodat de tekst gecentreerd blijft
            // in plaats van bovenaan te plakken.
            emptyContent.containerRelativeFrame(.vertical)
        }
        .scrollBounceBehavior(.always)
        .background(Theme.background)
    }

    private var vensterInUren: Int {
        Int(AppConfiguration.summaryWindow / 3600)
    }

    private var emptyContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundStyle(Theme.textSecondary)
            Text("Nog geen samenvattingen")
                .font(Theme.title(22))
            // Benoemt het venster: zonder die uitleg lijkt een rustige dag op een storing.
            Text(
                "Vandaag vat de artikelen van de afgelopen \(vensterInUren) uur samen. "
                    + "Staat hier niets, dan is er in die periode niets binnengekomen — "
                    + "de artikelen zelf blijven gewoon in Artikelen en Bewaard staan."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var clusterList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(clusters, id: \.topicName) { cluster in
                    TopicSummaryCardView(cluster: cluster)
                }
            }
            .padding()
        }
        .background(Theme.background)
    }
}

/// Kaart per onderwerp op Vandaag: de samenvatting zelf — beweringen met bronchips,
/// bronduiding en fact-checkwaarschuwing — in plaats van een link naar de samenvatting.
struct TopicSummaryCardView: View {
    let cluster: TopicCluster

    @State private var isExpanded = false

    private var accent: Color { Theme.brandColor(for: cluster.topicName) }

    private var visibleStatements: [SummaryStatement] {
        isExpanded
            ? cluster.statements
            : Array(cluster.statements.prefix(AppConfiguration.summaryCardCollapsedStatementCount))
    }

    private var sourceCountLabel: String {
        cluster.sourceCount == 1 ? "1 bron" : "\(cluster.sourceCount) bronnen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: SummaryDetailView(cluster: cluster)) {
                header
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(visibleStatements) { statement in
                    StatementRowView(statement: statement, itemsByID: cluster.itemsByID, accent: accent)
                }
            }

            if cluster.statements.count > AppConfiguration.summaryCardCollapsedStatementCount {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Toon minder" : "Toon meer")
                        .font(.subheadline.bold())
                }
                .tint(accent)
            }

            TopicSourceRatingView(cluster: cluster)

            if cluster.hasDisputedClaim {
                FactCheckWarningView(results: cluster.disputedFactChecks, compact: true)
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(cluster.topicName.uppercased())
                .font(Theme.headline(15))
                .foregroundStyle(accent)
            Spacer()
            Text(sourceCountLabel)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
