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
    /// Telt op bij een herhaalde tik op de tab Artikelen; de lijst scrolt dan naar boven.
    @State private var articlesScrollToTop = 0
    @State private var lastClusteredAt: Date? = nil
    /// Resultaat van een feed-toevoeging via `rssreader://add` (#203), getoond als korte alert.
    @State private var feedToevoegMelding: FeedToevoegMelding? = nil

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
                scrollToTopTrigger: articlesScrollToTop,
                onRefreshComplete: { await regenerateSummaries() }
            )
            .tag(1)

            SavedArticlesView()
                .tag(2)
        }
        .floatingTabBar(selection: $selectedTab) { tab in
            if tab == 1 { articlesScrollToTop += 1 }
        }
        .appThemeTint()
        .task {
            await refreshAndCluster()
        }
        .onOpenURL { url in
            // rssreader://add?url=<feed-url> (#203): sneltoevoegen zonder Share Sheet, bv.
            // vanuit Spotlight, Snelkoppelingen of een geplakte link in Safari. Elke andere
            // rssreader://-aanroep (OAuth-callback) blijft bij de bestaande routering; alleen
            // dit pad met host "add" wordt hier afgevangen.
            guard url.scheme == "rssreader", url.host == "add" else {
                OAuthCallbackHandler.shared.handle(url: url)
                return
            }
            Task { await handleAddFeedURL(url) }
        }
        .alert(item: $feedToevoegMelding) { melding in
            Alert(
                title: Text(melding.titel),
                message: Text(melding.bericht),
                dismissButton: .default(Text("Oké"))
            )
        }
    }

    /// Verwerkt `rssreader://add?url=<feed-url>`: geeft de meegegeven URL door aan de
    /// bestaande feed-toevoeglogica (`FeedAddingService`, #201) en toont een korte melding
    /// bij succes of fout. Geen tussenscherm, net als de Share Extension (#201).
    private func handleAddFeedURL(_ url: URL) async {
        guard
            let rawURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
            !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            feedToevoegMelding = FeedToevoegMelding(
                titel: "Feed toevoegen mislukt",
                bericht: "Geen geldige url-parameter meegegeven. Gebruik rssreader://add?url=<feed-url>.",
                isSucces: false
            )
            return
        }

        do {
            let feed = try await FeedAddingService.addFeed(from: rawURL, context: modelContext)
            // Volledige verversing erbovenop, zoals bij AddFeedView: bronbeoordeling,
            // mapindeling en consistente ontdubbeling.
            await refreshService.refresh(feed: feed, context: modelContext)
            feedToevoegMelding = FeedToevoegMelding(
                titel: "Feed toegevoegd",
                bericht: "'\(feed.title)' is toegevoegd aan FableFlux.",
                isSucces: true
            )
        } catch let error as FeedAddError {
            feedToevoegMelding = FeedToevoegMelding(
                titel: "Feed toevoegen mislukt",
                bericht: error.errorDescription ?? "Feed kon niet worden toegevoegd.",
                isSucces: false
            )
        } catch {
            feedToevoegMelding = FeedToevoegMelding(
                titel: "Feed toevoegen mislukt",
                bericht: "Feed kon niet worden toegevoegd: \(error.localizedDescription)",
                isSucces: false
            )
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

/// Feedback over een feed-toevoeging via het `rssreader://add`-URL-schema (#203), getoond
/// als korte alert — zelfde eenmalige presentatiepatroon als `OpslagFoutmelding`
/// (`PersistenceService.swift`), maar voor zowel een succes- als een foutmelding.
struct FeedToevoegMelding: Identifiable {
    let id = UUID()
    let titel: String
    let bericht: String
    let isSucces: Bool
}
