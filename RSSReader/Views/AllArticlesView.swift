import SwiftUI
import SwiftData

struct AllArticlesView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppConfiguration.UserDefaultsKeys.hideReadArticles) private var hideReadArticles = false
    @AppStorage(AppConfiguration.UserDefaultsKeys.articlesFolderFilter) private var folderFilterID = ""

    @Query(sort: \FeedFolder.sortOrder) private var folders: [FeedFolder]
    @Query private var feeds: [Feed]

    var refreshService: FeedRefreshService
    var onRefreshComplete: () async -> Void

    @State private var showFeedManagement = false

    /// Hoeveel artikelen de lijst nu ophaalt. Groeit terwijl je naar beneden scrolt en
    /// begint opnieuw zodra een filter wijzigt — dan kijk je immers naar een andere lijst.
    @State private var limit = AppConfiguration.articlePageSize

    /// Lege string of een verwijderde map betekent: geen filter.
    private var activeFolder: FeedFolder? {
        guard !folderFilterID.isEmpty else { return nil }
        return folders.first { $0.id.uuidString == folderFilterID }
    }

    /// De id's van de feeds in de actieve map, of `nil` als er geen mapfilter staat.
    /// Dit loopt over de feeds (tientallen), niet over de artikelen (duizenden): het
    /// artikelenscherm filterde eerder per artikel op `$0.feed?.folder?.id`, en elke
    /// stap daarvan laadde een `Feed` en een `FeedFolder` in vanuit de database — op
    /// de main thread (#108).
    private var activeFeedIDs: [UUID]? {
        guard let activeFolder else { return nil }
        return feeds.filter { $0.folder?.id == activeFolder.id }.map(\.id)
    }

    var body: some View {
        NavigationStack {
            ArticleListView(
                hideRead: hideReadArticles,
                feedIDs: activeFeedIDs,
                limit: limit,
                onReachEnd: { limit += AppConfiguration.articlePageSize },
                onRefresh: { await refreshFeeds() },
                emptyState: { emptyState }
            )
            .onChange(of: hideReadArticles) { limit = AppConfiguration.articlePageSize }
            .onChange(of: folderFilterID) { limit = AppConfiguration.articlePageSize }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !folders.isEmpty {
                    filterBar
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Artikelen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if refreshService.isRefreshing {
                        ProgressView()
                    } else {
                        Button("Vernieuwen", systemImage: "arrow.clockwise") {
                            Task { await refreshFeeds() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Feeds beheren", systemImage: "list.bullet.rectangle") {
                            showFeedManagement = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $showFeedManagement) {
                FeedListView(
                    refreshService: refreshService,
                    onRefreshComplete: onRefreshComplete
                )
            }
        }
    }

    /// Drie situaties met een eigen uitleg: geen feeds, een filter dat niets oplevert,
    /// of feeds die (nog) geen artikelen hebben.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            if feeds.isEmpty {
                Text("Nog geen feeds")
                    .font(.title2.bold())
                Text("Voeg RSS-feeds toe; hun artikelen verschijnen hier.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Feeds beheren") { showFeedManagement = true }
                    .buttonStyle(.borderedProminent)
            } else if let activeFolder {
                Text("Geen artikelen in \(activeFolder.name)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("De feeds in deze map hebben nog geen artikelen. Kies \"Alle\" om alles te zien.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Toon alle artikelen") { folderFilterID = "" }
                    .buttonStyle(.bordered)
            } else {
                Text("Nog geen artikelen")
                    .font(.title2.bold())
                Text(
                    hideReadArticles
                        ? "Alles is gelezen. Vernieuw om nieuwe artikelen op te halen."
                        : "Vernieuw om artikelen op te halen."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
        }
        .padding()
    }

    private func refreshFeeds() async {
        await refreshService.refreshAll(feeds: feeds, context: modelContext)
        await onRefreshComplete()
    }

    /// Staat buiten het scrollgebied (safe-area inset), dus blijft staan tijdens het scrollen.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "Alle", id: "")
                ForEach(folders) { folder in
                    filterChip(title: folder.name, id: folder.id.uuidString)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func filterChip(title: String, id: String) -> some View {
        let isActive = (activeFolder?.id.uuidString ?? "") == id

        return Button {
            folderFilterID = id
        } label: {
            Text(title)
                .font(Theme.categoryLabel(13))
                .foregroundStyle(isActive ? Color.white : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isActive {
                        Capsule().fill(Theme.accent)
                    } else {
                        Capsule().fill(Theme.card)
                            .overlay(Capsule().strokeBorder(Theme.textSecondary.opacity(0.25), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// De artikelenlijst zelf, met een `@Query` die het filteren aan SQLite overlaat.
///
/// Waarom dit een eigen view is: `@Query` krijgt zijn predicaat bij initialisatie, en
/// `@AppStorage`-waarden zijn daar nog niet beschikbaar. `AllArticlesView` leest de
/// instellingen en geeft ze hier als gewone parameters door; de `init` bouwt daarmee het
/// predicaat. Wijzigt een van die parameters, dan maakt SwiftUI de view opnieuw aan en
/// draait de query met het nieuwe predicaat (#108).
private struct ArticleListView<EmptyState: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [FeedItem]

    /// De gevraagde limiet. Zijn er precies zoveel artikelen geladen, dan kunnen er meer
    /// zijn; is het er minder, dan is dit het einde van de lijst.
    private let limit: Int
    private let onReachEnd: () -> Void
    private let onRefresh: () async -> Void
    private let emptyState: () -> EmptyState

    @State private var opslagFout: OpslagFoutmelding?

    init(
        hideRead: Bool,
        feedIDs: [UUID]?,
        limit: Int,
        onReachEnd: @escaping () -> Void,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder emptyState: @escaping () -> EmptyState
    ) {
        self.limit = limit
        self.onReachEnd = onReachEnd
        self.onRefresh = onRefresh
        self.emptyState = emptyState

        _items = Query(ArticleFilter.descriptor(hideRead: hideRead, feedIDs: feedIDs, limit: limit))
    }

    var body: some View {
        List {
            ForEach(items, id: \.id) { item in
                ZStack {
                    FeedItemCard(item: item)
                    // De ZStack met een onzichtbare link verbergt de disclosure-chevron
                    // die een List aan een NavigationLink hangt. De link geeft een waarde
                    // door in plaats van een destination: een destination-link bouwt zijn
                    // bestemming meteen op, dus elke gerealiseerde rij construeerde een
                    // volledige ArticlePageView met de hele lijst erin (#115).
                    NavigationLink(value: item.id) {
                        EmptyView()
                    }
                    .opacity(0)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                // Bij de laatste rij een pagina bijladen. `items.count == limit` betekent
                // dat de database er precies zoveel gaf als gevraagd; dan zijn er
                // waarschijnlijk meer. Gaf hij er minder, dan is dit het einde.
                .onAppear {
                    if item.id == items.last?.id, items.count == limit {
                        onReachEnd()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        item.isRead.toggle()
                        modelContext.saveOrLog("de gelezen-markering te bewaren")
                    } label: {
                        Label(
                            item.isRead ? "Ongelezen" : "Gelezen",
                            systemImage: item.isRead ? "envelope.badge" : "envelope.open"
                        )
                    }
                    .tint(.gray)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        item.isSaved.toggle()
                        modelContext.saveOrReport("de bewaarstatus van het artikel te wijzigen", melding: &opslagFout)
                    } label: {
                        Label(
                            item.isSaved ? "Niet bewaard" : "Bewaar",
                            systemImage: item.isSaved ? "bookmark.slash" : "bookmark"
                        )
                    }
                    .tint(Theme.accentSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Eén bestemming voor de hele lijst in plaats van één per rij. De index wordt
        // pas opgezocht wanneer er daadwerkelijk genavigeerd wordt; dat is één keer
        // lineair zoeken bij een tik, in plaats van werk bij elke update.
        // `VastgelegdeArtikelPagina` legt de lijst bij het openen vast: met "gelezen
        // verbergen" aan valt het geopende artikel anders uit `items` en blijft het
        // scherm leeg (#139).
        .navigationDestination(for: UUID.self) { id in
            VastgelegdeArtikelPagina(id: id, items: items, onReachEnd: onReachEnd)
        }
        .refreshable { await onRefresh() }
        // Overlay in plaats van een vervangende view: de lijst blijft bestaan, dus
        // pull-to-refresh werkt ook wanneer er nog niets te tonen is.
        .overlay {
            if items.isEmpty {
                emptyState()
            }
        }
        .opslagFoutmelding($opslagFout)
    }
}

/// Bouwt het predicaat voor de artikelenlijst.
///
/// Los van de view, en met opzet niet `private`: een fout in een `#Predicate` blijkt pas
/// als hij draait, niet bij het compileren. Zo kan een test hem tegen een echte
/// in-memory store uitvoeren en vangt CI een stukgelopen predicaat (#108).
///
/// De mapfilter gebruikt `if let feed = item.feed` en niet `item.feed?.id`. Een optionele
/// keten maakt de macro stuk: van `?.id` verwacht hij een `KeyPath<Feed, UUID?>` terwijl
/// `id` niet-optioneel is, en een `??` eromheen levert een `Optional<Bool>` op waar `&&`
/// een `Bool` wil. De `if`-vorm moet daarom de hele body van de closure zijn — als
/// deel van een grotere expressie is een `if` in Swift geen expressie.
enum ArticleFilter {

    /// De volledige beschrijving waarmee de artikelenlijst zijn artikelen ophaalt.
    ///
    /// `relationshipKeyPathsForPrefetching` is hier het punt. Elke kaart in de lijst leest
    /// `item.feed` (voor de kleur, het bronlabel en de bias-indicatoren) en
    /// `item.factCheckResults`. Zonder prefetching haalt SwiftData die per rij afzonderlijk
    /// op: één databaseleesactie per relatie per zichtbare rij, synchroon op de main thread.
    /// De meting bij #106 laat dat zien als `ArticleListView.body.get` → `libsqlite3` →
    /// `pread`, met een main thread die wacht op schijf in plaats van rekent. Met
    /// prefetching komen die relaties in één keer mee.
    /// - Parameter limit: hoeveel artikelen er hooguit worden opgehaald; `nil` is alles.
    static func descriptor(
        hideRead: Bool,
        feedIDs: [UUID]?,
        limit: Int? = nil
    ) -> FetchDescriptor<FeedItem> {
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: predicate(hideRead: hideRead, feedIDs: feedIDs),
            sortBy: [SortDescriptor(\FeedItem.pubDate, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\FeedItem.feed, \FeedItem.factCheckResults]
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// - Parameters:
    ///   - hideRead: gelezen artikelen weglaten.
    ///   - feedIDs: alleen artikelen uit deze feeds; `nil` betekent geen mapfilter.
    static func predicate(hideRead: Bool, feedIDs: [UUID]?) -> Predicate<FeedItem> {
        switch (hideRead, feedIDs) {
        case (true, .some(let ids)):
            return #Predicate<FeedItem> { item in
                if let feed = item.feed {
                    item.isRead == false && ids.contains(feed.id)
                } else {
                    false
                }
            }
        case (false, .some(let ids)):
            return #Predicate<FeedItem> { item in
                if let feed = item.feed {
                    ids.contains(feed.id)
                } else {
                    false
                }
            }
        case (true, .none):
            return #Predicate<FeedItem> { item in item.isRead == false }
        case (false, .none):
            return #Predicate<FeedItem> { _ in true }
        }
    }
}
