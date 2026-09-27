import SwiftUI
import SwiftData

/// De artikelen van één feed.
///
/// Dun omhulsel om `FeedItemsList`: `@Query` krijgt zijn predicaat bij initialisatie, en
/// `@AppStorage` is daar nog niet beschikbaar (zelfde patroon als `ArticleListView`).
struct FeedItemsView: View {
    @AppStorage(AppConfiguration.UserDefaultsKeys.hideReadArticles) private var hideReadArticles = false
    let feed: Feed
    var refreshService: FeedRefreshService

    var body: some View {
        FeedItemsList(feed: feed, refreshService: refreshService, hideRead: hideReadArticles)
    }
}

/// Haalt de artikelen met één query op in plaats van via `feed.items` (#136). Die
/// relatie laadde elk artikel afzonderlijk, en na elke opslag opnieuw voor alle feeds
/// die samen waren opgehaald. De `@Query` werkt zelf bij na opslaan, dus nieuwe
/// artikelen na verversen verschijnen direct.
private struct FeedItemsList: View {
    @Environment(\.modelContext) private var modelContext
    let feed: Feed
    var refreshService: FeedRefreshService
    @Query private var sortedItems: [FeedItem]

    @State private var opslagFout: OpslagFoutmelding?
    @State private var geopend: FeedArtikel?

    init(feed: Feed, refreshService: FeedRefreshService, hideRead: Bool) {
        self.feed = feed
        self.refreshService = refreshService
        _sortedItems = Query(ArticleFilter.descriptor(hideRead: hideRead, feedIDs: [feed.id]))
    }

    var body: some View {
        List {
            ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                // Geen NavigationLink per rij: die verdwijnt met de rij (gelezen verbergen),
                // en dan verdwijnt ook het geopende artikel. Ook geen `NavigationLink(value:)`:
                // dit scherm wordt zelf via een destination geopend, en een waarde-link springt
                // dan terug naar de feedlijst in plaats van het artikel te tonen (#139).
                Button {
                    geopend = FeedArtikel(id: item.id)
                } label: {
                    FeedItemCard(item: item)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
                .contextMenu {
                    Button {
                        item.isSaved.toggle()
                        modelContext.saveOrReport("de bewaarstatus van het artikel te wijzigen", melding: &opslagFout)
                    } label: {
                        Label(
                            item.isSaved ? "Verwijder uit bewaard" : "Bewaar",
                            systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
                    }
                    Button {
                        item.isRead.toggle()
                        modelContext.saveOrLog("de gelezen-markering te bewaren")
                    } label: {
                        Label(
                            item.isRead ? "Markeer als ongelezen" : "Markeer als gelezen",
                            systemImage: item.isRead ? "envelope.badge" : "envelope.open")
                    }
                    if let link = item.link, let url = URL(string: link) {
                        ShareLink(item: url) { Label("Delen", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationDestination(item: $geopend) { artikel in
            VastgelegdeArtikelPagina(id: artikel.id, items: sortedItems)
        }
        .refreshable {
            await refreshService.refresh(feed: feed, context: modelContext)
        }
        .navigationTitle(feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .opslagFoutmelding($opslagFout)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Vernieuwen", systemImage: "arrow.clockwise") {
                    Task {
                        await refreshService.refresh(feed: feed, context: modelContext)
                    }
                }
                .disabled(refreshService.isRefreshing)
            }
        }
    }
}

/// Dunne wrapper zodat bestaande aanroepen (`FeedItemRowView`) de nieuwe card tonen.
struct FeedItemRowView: View {
    let item: FeedItem
    var body: some View { FeedItemCard(item: item) }
}

/// Magazine-card voor één artikel — "Glass Magazine"-stijl uit de PDF.
/// Afbeelding als banner bovenaan (indien aanwezig), Charter-titel, brand-accent per bron.
struct FeedItemCard: View {
    let item: FeedItem
    @AppStorage(AppConfiguration.UserDefaultsKeys.previewLineCount) private var previewLineCount = 2
    @AppStorage(AppConfiguration.UserDefaultsKeys.showArticleThumbnails) private var showArticleThumbnails = true
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize) private var articleFontSize = AppConfiguration
        .defaultArticleFontSize
    @AppStorage(AppConfiguration.UserDefaultsKeys.showBiasIndicators) private var showBiasIndicators = true

    /// Basisschaal die meebeweegt met Dynamic Type, met behoud van de gebruikersvoorkeur.
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 17

    private var titleSize: CGFloat { scaledBase * CGFloat(articleFontSize) / 17 }
    private var captionSize: CGFloat { max(titleSize - 4, 9) }
    private var metaSize: CGFloat { max(titleSize - 5, 8) }

    private var brand: Color {
        Theme.brandColor(for: item.feed?.title ?? item.feed?.url ?? "")
    }

    private var hasBanner: Bool {
        showArticleThumbnails && item.imageURL.flatMap { URL(string: $0) } != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasBanner, let urlString = item.imageURL, let url = URL(string: urlString) {
                bannerImage(url: url)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Categorie- / bron-label + ongelezen-indicator
                HStack(spacing: 6) {
                    if !item.isRead {
                        Circle().fill(brand).frame(width: 7, height: 7)
                    }
                    if let feedTitle = item.feed?.title {
                        Text(feedTitle.uppercased())
                            .font(Theme.categoryLabel(metaSize))
                            .tracking(0.8)
                            .foregroundStyle(brand)
                            .lineLimit(1)
                    }
                    if item.isVideoItem {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: metaSize))
                            .foregroundStyle(brand)
                    }
                    if item.isAudioItem {
                        Image(systemName: "waveform")
                            .font(.system(size: metaSize))
                            .foregroundStyle(brand)
                    }
                    Spacer(minLength: 0)
                    if item.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: metaSize))
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }

                // Titel in Charter (serif magazine-look)
                Text(item.title)
                    .font(Theme.title(titleSize + 1, relativeTo: .headline))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Korte beschrijving
                if previewLineCount > 0, !item.plainDescription.isEmpty {
                    Text(item.plainDescription)
                        .font(.system(size: captionSize))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(previewLineCount)
                }

                // Metadata
                if let date = item.pubDate {
                    Text(Self.relativeTime(for: date))
                        .font(.system(size: metaSize))
                        .foregroundStyle(Theme.textSecondary)
                }

                // Bronanalyse: bias-balk + betrouwbaarheidsbadge
                if showBiasIndicators, let feed = item.feed, let score = feed.biasScore {
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
                    .padding(.top, 2)
                }

                // Fact-check chip — alleen als resultaten beschikbaar zijn
                if showBiasIndicators, !item.factCheckResults.isEmpty {
                    FactCheckChipView(results: item.factCheckResults)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        // Schaduw, afronding en "gelezen" zonder offscreen passes (#122). Eerder lagen
        // schaduw, masker en doorzichtigheid op de hele kaart: CoreAnimation moest elke
        // kaart dan eerst apart tekenen, gemeten gemiddeld 69 passes per frame.
        // - De schaduw hangt aan een eenvoudige vorm achter de inhoud, niet aan de inhoud.
        // - Alleen de banner wordt afgeknipt; de achtergrondvorm is zelf al rond.
        // - "Gelezen" is een laag in de achtergrondkleur over de kaart in plaats van
        //   doorzichtigheid op de hele groep; het beeld is vrijwel gelijk.
        .background {
            Self.kaartvorm
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .overlay {
            // Alleen beeld: tikken op de bias-balk en de fact-check-chip moeten doorgaan.
            if item.isRead {
                Self.kaartvorm.fill(Theme.background.opacity(Self.gelezenDekking))
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            Self.kaartvorm.strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
    }

    private static let kaartvorm = RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
    /// Zelfde indruk als de vroegere `.opacity(0.72)`: 28% van de achtergrond erover.
    private static let gelezenDekking = 0.28

    /// De afbeelding mag de breedte van de kaart niet bepalen. `contentMode: .fill`
    /// maakt de view zo breed als de beeldverhouding vraagt (bij 3:1 is dat 504 pt bij
    /// een hoogte van 168), en een `.frame(maxWidth:)` erná kan een kind dat al een
    /// vaste maat heeft opgeëist niet meer kleiner maken — de kaart werd dan breder dan
    /// het scherm (#96). Daarom bepaalt een lege `Color.clear` het kader en hangt de
    /// afbeelding daar als overlay in: die kan het kader niet oprekken.
    @ViewBuilder
    private func bannerImage(url: URL) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        ZStack {
                            brand.opacity(0.12)
                            ProgressView()
                        }
                    case .failure:
                        ZStack {
                            brand.opacity(0.12)
                            Image(systemName: "photo").foregroundStyle(brand.opacity(0.5))
                        }
                    @unknown default:
                        brand.opacity(0.12)
                    }
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.cardCornerRadius, topTrailingRadius: Theme.cardCornerRadius,
                    style: .continuous))
    }

    /// Relatieve tijd zonder seconden: onder een minuut → "Zojuist".
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeTime(for date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) >= 60 else { return "Zojuist" }
        return relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }
}

/// Het geopende artikel in `FeedItemsView`, voor `navigationDestination(item:)`.
struct FeedArtikel: Hashable {
    let id: UUID
}

/// Het artikelscherm met de lijst zoals die was op het moment van openen (#139).
///
/// Openen markeert een artikel als gelezen. Met "gelezen verbergen" aan haalt de lijst
/// zich daarna opnieuw op zonder dat artikel, en een bestemming die het in de actuele
/// lijst opzoekt vindt het niet meer: een leeg scherm. Deze view legt de lijst bij het
/// openen vast in `@State` (die bewaart alleen de eerste waarde) en vult hem aan met
/// artikelen die er later bijkomen, zodat bijladen tijdens het vegen blijft werken.
struct VastgelegdeArtikelPagina: View {
    let id: UUID
    let actueel: [FeedItem]
    var onReachEnd: (() -> Void)?
    @State private var vastgelegd: [FeedItem]

    init(id: UUID, items: [FeedItem], onReachEnd: (() -> Void)? = nil) {
        self.id = id
        self.actueel = items
        self.onReachEnd = onReachEnd
        _vastgelegd = State(initialValue: items)
    }

    var body: some View {
        let lijst = Self.aangevuld(vastgelegd, met: actueel)
        if let index = lijst.firstIndex(where: { $0.id == id }) {
            ArticlePageView(items: lijst, initialIndex: index, onReachEnd: onReachEnd)
        }
    }

    /// De vastgelegde lijst, met daarachter de artikelen uit de actuele lijst die er nog
    /// niet in staan (bijgeladen pagina's). Wat intussen uit de actuele lijst viel, blijft.
    static func aangevuld(_ vastgelegd: [FeedItem], met actueel: [FeedItem]) -> [FeedItem] {
        let bekend = Set(vastgelegd.map(\.id))
        return vastgelegd + actueel.filter { !bekend.contains($0.id) }
    }
}

struct ArticlePageView: View {
    let items: [FeedItem]

    /// Wordt aangeroepen zodra je op het laatste geladen artikel belandt. De artikelenlijst
    /// laadt per pagina (#106); zonder dit stopt het vegen bij het laatst opgehaalde
    /// artikel. De andere schermen die deze view gebruiken pagineren niet en laten dit leeg.
    var onReachEnd: (() -> Void)?

    /// Id van het zichtbare artikel. Op id in plaats van index, zodat bijgeladen artikelen
    /// achteraan de positie niet verschuiven.
    @State private var currentID: UUID?

    init(items: [FeedItem], initialIndex: Int, onReachEnd: (() -> Void)? = nil) {
        self.items = items
        self.onReachEnd = onReachEnd
        self._currentID = State(initialValue: items.indices.contains(initialIndex) ? items[initialIndex].id : nil)
    }

    /// Hoe ver de uitgaande pagina meeschuift (0 = blijft staan, 1 = schuift gelijk op).
    private static let parallax: CGFloat = 0.3
    /// Hoeveel donkerder de uitgaande pagina wordt aan het einde van de veeg.
    private static let dimming: Double = 0.25

    /// Hoeveel pagina's aan weerszijden van de zichtbare al worden opgebouwd, zodat de tekst
    /// er staat zodra je veegt. De rest is een lege vlakte in de achtergrondkleur.
    private static let buren = 1

    // Geen pagina-TabView: die legt pagina's naast elkaar, en de naad daartussen liet een
    // smalle strook zien (#149). Hier overlappen pagina's: de volgende schuift óver de
    // vorige, die vertraagd meeschuift en donkerder wordt — het terugveeg-patroon van iOS.
    //
    // Geen LazyHStack: die bouwt een pagina pas als hij in beeld schuift, en dan verschijnt
    // de tekst pas tijdens de veeg. Een HStack met alleen de buren gevuld bouwt die vooraf.
    var body: some View {
        let huidige = items.firstIndex { $0.id == currentID } ?? 0
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Group {
                        if abs(index - huidige) <= Self.buren {
                            ItemDetailView(item: item, isActive: item.id == currentID)
                        } else {
                            Theme.background
                        }
                    }
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .containerRelativeFrame([.horizontal, .vertical])
                    .visualEffect { content, proxy in
                        let breedte = max(proxy.size.width, 1)
                        // Negatief zodra de pagina naar links uit beeld schuift.
                        let links = min(proxy.frame(in: .scrollView).minX, 0)
                        // Helemaal voorbij: onzichtbaar. Door de parallax ligt de vorige pagina
                        // anders ook in rust onder de huidige en schijnt hij door de afgeronde hoeken.
                        let voorbij = links <= -breedte + 0.5
                        return
                            content
                            .offset(x: -links * (1 - Self.parallax))
                            .brightness(Double(links / breedte) * Self.dimming)
                            .opacity(voorbij ? 0 : 1)
                    }
                    // Latere pagina's bovenop: de volgende schuift over de vorige heen.
                    .zIndex(Double(index))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .onChange(of: currentID, initial: true) { _, id in
            if id != nil, id == items.last?.id { onReachEnd?() }
        }
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .bottom)
    }
}
