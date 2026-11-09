import SwiftData
import SwiftUI

/// Andere artikelen over hetzelfde verhaal, voor de contextlaag in het leesscherm (#226).
@MainActor
enum StoryContext {
    /// Hoeveel recente artikelen meedoen aan het clusteren. Genoeg voor een dag nieuws uit
    /// tientallen feeds; het clusteren is kwadratisch, dus niet onbegrensd.
    static let candidateLimit = 400

    /// Artikelen uit andere feeds die `EventClusteringService` bij hetzelfde verhaal indeelt,
    /// nieuwste eerst. Leeg als er geen verhaalgroep is.
    static func relatedItems(for item: FeedItem, context: ModelContext, now: Date = Date()) -> [FeedItem] {
        guard item.feed?.isMastodonFeed != true else { return [] }
        let windowStart = now.addingTimeInterval(-72 * 3_600)
        guard (item.pubDate ?? .distantPast) >= windowStart else { return [] }
        let distantPast = Date.distantPast
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { ($0.pubDate ?? distantPast) >= windowStart },
            sortBy: [SortDescriptor(\FeedItem.pubDate, order: .reverse)]
        )
        descriptor.fetchLimit = candidateLimit
        descriptor.relationshipKeyPathsForPrefetching = [\FeedItem.feed]
        guard var candidates = try? context.fetch(descriptor) else { return [] }
        if !candidates.contains(where: { $0.id == item.id }) { candidates.append(item) }
        return related(to: item, in: EventClusteringService.shared.cluster(items: candidates))
    }

    /// Puur deel, los te testen: de andere artikelen uit de cluster van `item`.
    static func related(to item: FeedItem, in clusters: [EventCluster]) -> [FeedItem] {
        guard let cluster = clusters.first(where: { $0.items.contains { $0.id == item.id } }) else { return [] }
        return cluster.items.filter { $0.id != item.id && $0.feed?.id != item.feed?.id }
    }
}

/// De contextlaag (#226, schets 3C): bronduiding, andere bronnen over hetzelfde verhaal en
/// factchecks. Standaard ingeklapt als lipje boven de actiecapsule; dit is de uitgeklapte sheet.
struct ArticleContextSheet: View {
    let item: FeedItem
    let related: [FeedItem]

    /// Tekst op het lipje, of `nil` als er geen lipje hoort: zonder verhaalgroep en zonder
    /// factcheck is er geen context om te tonen.
    static func lipLabel(relatedCount: Int, hasFactCheck: Bool) -> String? {
        switch (relatedCount > 1, hasFactCheck) {
        case (true, true): return "Context · \(relatedCount) bronnen · factcheck"
        case (true, false): return "Context · \(relatedCount) bronnen"
        case (false, true): return "Context · factcheck"
        case (false, false): return nil
        }
    }

    /// Eén artikel per andere bron: de spreiding gaat over bronnen, niet over artikelen.
    private var otherSources: [FeedItem] {
        var seen = Set<UUID>()
        return related.filter { item in
            guard let id = item.feed?.id else { return false }
            return seen.insert(id).inserted
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let feed = item.feed {
                    Section("Deze bron") {
                        sourceRow(feed)
                    }
                }

                if !otherSources.isEmpty {
                    Section("Zelfde verhaal bij andere bronnen") {
                        ForEach(otherSources, id: \.id) { other in
                            NavigationLink {
                                ItemDetailView(item: other)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(other.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(3)
                                    if let feed = other.feed {
                                        sourceRow(feed)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if !item.factCheckResults.isEmpty {
                    Section("Factcheck") {
                        FactCheckChipView(results: item.factCheckResults)
                    }
                }
            }
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func sourceRow(_ feed: Feed) -> some View {
        if let score = feed.biasScore {
            HStack(alignment: .center, spacing: 8) {
                BiasBarView(
                    biasScore: score,
                    feedName: feed.title,
                    reliabilityLevel: feed.reliabilityLevel,
                    ratingSource: feed.ratingSource,
                    biasRatedAt: feed.biasRatedAt
                )
                ReliabilityBadgeView(level: feed.reliabilityLevel)
            }
        } else {
            HStack {
                Text(feed.title).font(.footnote)
                Spacer()
                Text("Geen beoordeling").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Aa in de actiecapsule: tekstgrootte en lettertype, zonder naar Instellingen te gaan.
struct ReadingSettingsPopover: View {
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize) private var fontSize = AppConfiguration
        .defaultArticleFontSize
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontFamily) private var fontFamily = AppConfiguration
        .defaultArticleFontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    fontSize = max(14, fontSize - 1)
                } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Kleinere tekst")
                // Zelfde schaal als Instellingen: 80–150% van de standaardgrootte.
                Text("\(Int((Double(fontSize) / Double(AppConfiguration.defaultArticleFontSize) * 100).rounded()))%")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 56)
                Button {
                    fontSize = min(26, fontSize + 1)
                } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Grotere tekst")
            }
            Picker("Lettertype", selection: $fontFamily) {
                Text("Charter").tag("charter")
                Text("SF Pro").tag("system")
                Text("New York").tag("newyork")
                Text("Georgia").tag("georgia")
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(minWidth: 300)
    }
}
