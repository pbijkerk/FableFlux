//
//  ArticleFilterTests.swift
//  RSSReaderTests
//

import SwiftData
import XCTest

@testable import RSSReader

/// Voert het predicaat van de artikelenlijst uit tegen een echte in-memory store (#108).
///
/// Waarom tegen een echte store: een fout in een `#Predicate` blijkt pas als hij draait.
/// Compileren zegt niets — SwiftData vertaalt het predicaat pas bij het ophalen naar een
/// query, en struikelt daar over vormen die de compiler wel accepteert.
@MainActor
final class ArticleFilterTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Feed.self, FeedItem.self, FeedFolder.self, Topic.self,
            TopicSummary.self, FactCheckResult.self, MastodonAccount.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    /// Twee mappen, elk met één feed, plus een losse feed zonder map.
    /// Titels: "tech-gelezen", "tech-ongelezen", "sport-ongelezen", "los-ongelezen".
    @discardableResult
    private func maakTestdata() -> (techFeed: Feed, sportFeed: Feed, losseFeed: Feed) {
        let context = container.mainContext

        let techMap = FeedFolder(name: "Tech", sortOrder: 0)
        let sportMap = FeedFolder(name: "Sport", sortOrder: 1)
        context.insert(techMap)
        context.insert(sportMap)

        let tech = Feed(url: "https://tech.example/rss", title: "Tech")
        tech.folder = techMap
        let sport = Feed(url: "https://sport.example/rss", title: "Sport")
        sport.folder = sportMap
        let los = Feed(url: "https://los.example/rss", title: "Los")
        for feed in [tech, sport, los] { context.insert(feed) }

        func voegToe(_ titel: String, aan feed: Feed, gelezen: Bool) {
            let item = FeedItem(title: titel, pubDate: Date(timeIntervalSince1970: 1_700_000_000))
            item.isRead = gelezen
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
        }

        voegToe("tech-gelezen", aan: tech, gelezen: true)
        voegToe("tech-ongelezen", aan: tech, gelezen: false)
        voegToe("sport-ongelezen", aan: sport, gelezen: false)
        voegToe("los-ongelezen", aan: los, gelezen: false)

        return (tech, sport, los)
    }

    private func titels(hideRead: Bool, feedIDs: [UUID]?) throws -> Set<String> {
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: ArticleFilter.predicate(hideRead: hideRead, feedIDs: feedIDs)
        )
        return Set(try container.mainContext.fetch(descriptor).map(\.title))
    }

    func testZonderFiltersKomtAllesTerug() throws {
        maakTestdata()
        XCTAssertEqual(
            try titels(hideRead: false, feedIDs: nil),
            ["tech-gelezen", "tech-ongelezen", "sport-ongelezen", "los-ongelezen"])
    }

    func testGelezenVerbergenLaatAlleenOngelezenZien() throws {
        maakTestdata()
        XCTAssertEqual(
            try titels(hideRead: true, feedIDs: nil),
            ["tech-ongelezen", "sport-ongelezen", "los-ongelezen"])
    }

    func testMapfilterLaatAlleenDeFeedsUitDieMapZien() throws {
        let feeds = maakTestdata()
        XCTAssertEqual(
            try titels(hideRead: false, feedIDs: [feeds.techFeed.id]),
            ["tech-gelezen", "tech-ongelezen"])
    }

    func testMapfilterEnGelezenVerbergenSamen() throws {
        let feeds = maakTestdata()
        XCTAssertEqual(
            try titels(hideRead: true, feedIDs: [feeds.techFeed.id]),
            ["tech-ongelezen"])
    }

    func testMeerdereFeedsInEenMap() throws {
        let feeds = maakTestdata()
        XCTAssertEqual(
            try titels(hideRead: false, feedIDs: [feeds.techFeed.id, feeds.sportFeed.id]),
            ["tech-gelezen", "tech-ongelezen", "sport-ongelezen"])
    }

    /// Een lege map hoort niets te tonen, niet stiekem alles.
    func testLegeMapLevertNiets() throws {
        maakTestdata()
        XCTAssertTrue(try titels(hideRead: false, feedIDs: []).isEmpty)
    }

    // MARK: - De beschrijving

    /// De descriptor draait hetzelfde filter én vraagt de relaties vooruit op. Dat laatste
    /// is niet aan de uitkomst te zien, maar wel of het de fetch stukmaakt: een verkeerd
    /// keypath in `relationshipKeyPathsForPrefetching` blijkt pas als hij draait (#106).
    func testDeBeschrijvingFiltertEnSorteertNieuwsteEerst() throws {
        let context = container.mainContext
        let feed = Feed(url: "https://tech.example/rss", title: "Tech")
        context.insert(feed)

        for (index, titel) in ["oudst", "midden", "nieuwst"].enumerated() {
            let item = FeedItem(
                title: titel,
                pubDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600))
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
        }

        let opgehaald = try context.fetch(ArticleFilter.descriptor(hideRead: false, feedIDs: nil))

        XCTAssertEqual(
            opgehaald.map(\.title), ["nieuwst", "midden", "oudst"],
            "De lijst hoort nieuwste-eerst te staan")
        XCTAssertEqual(
            opgehaald.first?.feed?.title, "Tech",
            "De vooruit opgehaalde relatie hoort gewoon leesbaar te zijn")
    }

    func testDeBeschrijvingRespecteertBeideFilters() throws {
        let feeds = maakTestdata()
        let opgehaald = try container.mainContext.fetch(
            ArticleFilter.descriptor(hideRead: true, feedIDs: [feeds.techFeed.id]))

        XCTAssertEqual(opgehaald.map(\.title), ["tech-ongelezen"])
    }

    // MARK: - Paginering

    /// Bouwt `aantal` artikelen, oplopend in tijd: "artikel 0" is het oudst.
    private func maakOplopendeArtikelen(_ aantal: Int) {
        let context = container.mainContext
        let feed = Feed(url: "https://example.com/rss", title: "Testfeed")
        context.insert(feed)

        for index in 0..<aantal {
            let item = FeedItem(
                title: "artikel \(index)",
                pubDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600))
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
        }
    }

    func testDeLimietGeeftDeNieuwsteArtikelen() throws {
        maakOplopendeArtikelen(5)
        let opgehaald = try container.mainContext.fetch(
            ArticleFilter.descriptor(hideRead: false, feedIDs: nil, limit: 2))

        XCTAssertEqual(
            opgehaald.map(\.title), ["artikel 4", "artikel 3"],
            "Een limiet knipt onderaan af, niet bovenaan: de nieuwste horen te blijven")
    }

    /// De lijst laadt bij zodra er precies zoveel artikelen terugkomen als gevraagd.
    /// Komt er minder terug, dan is dat het einde — dat onderscheid moet kloppen.
    func testEenLimietGroterDanDeVoorraadGeeftAlles() throws {
        maakOplopendeArtikelen(3)
        let opgehaald = try container.mainContext.fetch(
            ArticleFilter.descriptor(hideRead: false, feedIDs: nil, limit: 50))

        XCTAssertEqual(opgehaald.count, 3, "Minder dan de limiet betekent: dit is het einde")
    }

    func testZonderLimietKomtAllesTerug() throws {
        maakOplopendeArtikelen(5)
        let opgehaald = try container.mainContext.fetch(
            ArticleFilter.descriptor(hideRead: false, feedIDs: nil))

        XCTAssertEqual(opgehaald.count, 5)
    }

    func testDeLimietWerktSamenMetDeFilters() throws {
        let feeds = maakTestdata()
        let opgehaald = try container.mainContext.fetch(
            ArticleFilter.descriptor(hideRead: true, feedIDs: [feeds.techFeed.id], limit: 10))

        XCTAssertEqual(
            opgehaald.map(\.title), ["tech-ongelezen"],
            "De limiet mag het filter niet omzeilen")
    }

    // MARK: - Randgevallen

    /// Een artikel zonder feed hoort buiten elke mapfilter te vallen. Dat is de `else`-tak
    /// van het predicaat.
    func testArtikelZonderFeedValtBuitenEenMapfilter() throws {
        let feeds = maakTestdata()
        let wees = FeedItem(title: "zonder feed", pubDate: Date(timeIntervalSince1970: 1_700_000_000))
        container.mainContext.insert(wees)

        XCTAssertFalse(try titels(hideRead: false, feedIDs: [feeds.techFeed.id]).contains("zonder feed"))
        XCTAssertTrue(
            try titels(hideRead: false, feedIDs: nil).contains("zonder feed"),
            "Zonder mapfilter hoort het artikel er gewoon bij te staan")
    }

    // MARK: - Feed- en mapweergave (#136)

    /// `FeedItemsView` en `FolderItemsView` bouwden hun lijst uit `feed.items`, gefilterd
    /// en gesorteerd in het geheugen. De query moet dezelfde artikelen in dezelfde volgorde
    /// opleveren: nieuwste eerst, zonder datum achteraan.
    private func oudeLijst(_ feeds: [Feed], hideRead: Bool) -> [String] {
        feeds.flatMap { $0.items }
            .filter { hideRead ? !$0.isRead : true }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .map(\.title)
    }

    private func maakFeedsMetDatums() throws -> (map: FeedFolder, feeds: [Feed], buiten: Feed) {
        let context = container.mainContext
        let map = FeedFolder(name: "Map", sortOrder: 0)
        context.insert(map)
        var feeds: [Feed] = []
        for f in 0..<3 {
            let feed = Feed(url: "https://f\(f).example/rss", title: "F\(f)")
            feed.folder = map
            context.insert(feed)
            feeds.append(feed)
            for i in 0..<5 {
                // Datums door elkaar tussen feeds, één zonder datum per feed.
                let datum: Date? = i == 4 ? nil : Date(timeIntervalSince1970: Double(1_700_000_000 + (i * 3 + f) * 60))
                let item = FeedItem(title: "F\(f)-\(i)", pubDate: datum)
                item.isRead = i % 2 == 0
                item.feed = feed
                context.insert(item)
            }
        }
        let buiten = Feed(url: "https://buiten.example/rss", title: "Buiten")
        context.insert(buiten)
        let item = FeedItem(title: "Buiten-0", pubDate: Date(timeIntervalSince1970: 1_800_000_000))
        item.feed = buiten
        context.insert(item)
        try context.save()
        return (map, feeds, buiten)
    }

    private func nieuweLijst(feedIDs: [UUID], hideRead: Bool) throws -> [String] {
        try container.mainContext
            .fetch(ArticleFilter.descriptor(hideRead: hideRead, feedIDs: feedIDs))
            .map(\.title)
    }

    func testFeedweergaveGelijkAanOudeLijst() throws {
        let (_, feeds, _) = try maakFeedsMetDatums()
        for hideRead in [false, true] {
            let nieuw = try nieuweLijst(feedIDs: [feeds[1].id], hideRead: hideRead)
            XCTAssertEqual(
                nieuw.filter { !$0.hasSuffix("-4") },
                oudeLijst([feeds[1]], hideRead: hideRead).filter { !$0.hasSuffix("-4") },
                "hideRead=\(hideRead)")
            XCTAssertEqual(Set(nieuw), Set(oudeLijst([feeds[1]], hideRead: hideRead)), "hideRead=\(hideRead)")
        }
    }

    func testMapweergaveGelijkAanOudeLijst() throws {
        let (map, _, _) = try maakFeedsMetDatums()
        for hideRead in [false, true] {
            let nieuw = try nieuweLijst(feedIDs: map.feeds.map(\.id), hideRead: hideRead)
            let oud = oudeLijst(map.feeds, hideRead: hideRead)
            XCTAssertEqual(Set(nieuw), Set(oud), "hideRead=\(hideRead)")
            XCTAssertFalse(nieuw.contains("Buiten-0"), "Een feed buiten de map telt niet mee")
            // Artikelen met datum staan in dezelfde volgorde; zonder datum komen ze achteraan.
            let metDatum = nieuw.filter { !$0.hasSuffix("-4") }
            XCTAssertEqual(metDatum, oud.filter { !$0.hasSuffix("-4") }, "hideRead=\(hideRead)")
            XCTAssertEqual(Set(nieuw.suffix(nieuw.count - metDatum.count)), Set(nieuw.filter { $0.hasSuffix("-4") }))
        }
    }
}
