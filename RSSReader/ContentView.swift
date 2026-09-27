import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var feeds: [Feed]
    @Query private var topics: [Topic]

    @State private var refreshService = FeedRefreshService()
    @State private var clusteringService = TopicClusteringService()

    @State private var clusters: [TopicCluster] = []
    @State private var selectedTab = 0
    @State private var lastClusteredAt: Date? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            SummaryListView(
                clusters: $clusters,
                isLoading: clusteringService.isClustering || refreshService.isRefreshing,
                onRefresh: { await refreshAndCluster(force: true) }
            )
            .tag(0)

            AllArticlesView(
                refreshService: refreshService,
                onRefreshComplete: { await regenerateSummaries() }
            )
            .tag(1)

            SavedArticlesView()
                .tag(2)
        }
        .floatingTabBar(selection: $selectedTab)
        .appThemeTint()
        .task {
            await refreshAndCluster()
        }
        .onOpenURL { url in
            OAuthCallbackHandler.shared.handle(url: url)
        }
    }

    /// `force` slaat de debounce over: bij een expliciete pull vraagt de gebruiker er zelf
    /// om en hoort hij een nieuw resultaat te zien, ook binnen twee minuten.
    private func refreshAndCluster(force: Bool = false) async {
        await refreshService.refreshAll(feeds: feeds, context: modelContext)

        let shouldCluster =
            force
            || (lastClusteredAt.map { Date().timeIntervalSince($0) > AppConfiguration.clusteringDebounce } ?? true)
        guard shouldCluster else { return }

        // regenerateSummaries() zet lastClusteredAt zelf, op het moment dat de clustering
        // klaar is. Hier niets meer overschrijven: dat zou de klok terugzetten naar vóór
        // het ophalen en clusteren, waardoor de debounce te vroeg vervalt.
        await regenerateSummaries()
    }

    private func regenerateSummaries() async {
        // Alleen feeds die de gebruiker in de samenvatting wil; hun artikelen blijven
        // wel gewoon zichtbaar in Artikelen en Bewaard.
        // Alleen artikelen binnen het recentheidsvenster: een samenvatting van "Vandaag"
        // hoort niet uit de volle bewaarperiode te putten (#89).
        // Eén query met venster en feedkeuze in het predicaat (#120). Mislukt die, dan de
        // oude route: trager, maar de samenvatting blijft werken.
        let recenteItems: [FeedItem]
        do {
            recenteItems = try modelContext.fetch(TopicClusteringService.summaryItemsDescriptor())
        } catch {
            recenteItems = TopicClusteringService.withinSummaryWindow(
                feeds.filter { $0.includedInSummary }.flatMap { $0.items }
            )
        }
        let apiKey =
            KeychainService.load(forKey: AppConfiguration.KeychainKeys.claudeAPIKey)
            ?? UserDefaults.standard.string(forKey: AppConfiguration.UserDefaultsKeys.claudeAPIKey)
            ?? ""
        // nil betekent: verdrongen door een nieuwere ronde of geannuleerd. Het bestaande
        // resultaat laten staan; de ronde die won werkt de samenvatting zelf bij.
        guard
            let result = await clusteringService.cluster(
                items: recenteItems,
                savedTopics: topics,
                claudeAPIKey: apiKey.isEmpty ? nil : apiKey
            )
        else { return }

        clusters = result
        lastClusteredAt = Date()
    }
}
