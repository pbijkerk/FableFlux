//
//  ReadLaterTests.swift
//  FableFluxTests
//

import SwiftData
import XCTest

@testable import FableFlux

/// Regels voor Lees later en Bewaard (#224): termijn vanaf toevoegen, verlopen naar de
/// gewone opruimtermijn, Bewaard nooit opruimen, en import/export met status.
@MainActor
final class ReadLaterTests: XCTestCase {

    private var container: ModelContainer!
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)
    private let dag: TimeInterval = 24 * 3600

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

    private func feedMet(_ items: [FeedItem], retentionDays: Int? = 30) -> (Feed, ModelContext) {
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/rss", title: "Testfeed")
        feed.retentionDays = retentionDays
        context.insert(feed)
        for item in items {
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
        }
        return (feed, context)
    }

    private func titels(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<FeedItem>()).map(\.title).sorted()
    }

    // MARK: - Status

    func testStatusVolgtUitDeVelden() {
        let item = FeedItem(title: "A")
        XCTAssertEqual(item.laterStatus, .regular)
        ReadLater.addToReadLater(item, now: nu)
        XCTAssertEqual(item.laterStatus, .readLater)
        ReadLater.save(item, now: nu)
        XCTAssertEqual(item.laterStatus, .saved)
        XCTAssertNil(item.readLaterAddedAt, "Bewaren haalt het artikel uit Lees later")
        XCTAssertEqual(item.savedAt, nu)
    }

    func testBewaardVanVoor224BlijftBewaard() {
        // Een rij van vóór #224 heeft alleen `isSaved`; die moet onder Bewaard staan.
        let oud = FeedItem(title: "Oud bewaard", pubDate: nu.addingTimeInterval(-90 * dag))
        oud.isSaved = true
        XCTAssertEqual(oud.laterStatus, .saved)
        XCTAssertNil(oud.savedAt)
        XCTAssertEqual(oud.savedSortDate, oud.pubDate, "Zonder savedAt sorteert het op de eigen datum")
    }

    func testBewaardArtikelKanNietInLeesLater() {
        let item = FeedItem(title: "A")
        ReadLater.save(item, now: nu)
        ReadLater.addToReadLater(item, now: nu)
        XCTAssertNil(item.readLaterAddedAt)
        XCTAssertEqual(item.laterStatus, .saved)
    }

    func testBewarenLegtLokaleKopieVast() {
        let item = FeedItem(title: "A", itemDescription: "<p>Feedtekst</p><script>x()</script>")
        ReadLater.save(item, now: nu)
        XCTAssertEqual(item.savedContentHTML, "<p>Feedtekst</p>", "Zonder volledige tekst: de feedtekst")
        ReadLater.save(item, contentHTML: "<p>Volledig artikel</p>", now: nu.addingTimeInterval(60))
        XCTAssertEqual(item.savedContentHTML, "<p>Volledig artikel</p>")
        XCTAssertEqual(item.savedAt, nu, "Opnieuw bewaren verschuift het bewaarmoment niet")
    }

    // MARK: - Termijn

    func testTermijnTeltVanafToevoegenNietVanafPublicatie() {
        let item = FeedItem(title: "Oud artikel", pubDate: nu.addingTimeInterval(-365 * dag))
        ReadLater.addToReadLater(item, now: nu)
        XCTAssertFalse(ReadLater.isExpired(item, termDays: 14, now: nu.addingTimeInterval(13 * dag)))
        XCTAssertTrue(ReadLater.isExpired(item, termDays: 14, now: nu.addingTimeInterval(14 * dag)))
    }

    func testDagenTeGaanEnWaarschuwingsvenster() {
        let item = FeedItem(title: "A")
        ReadLater.addToReadLater(item, now: nu)
        XCTAssertEqual(ReadLater.daysLeft(item, termDays: 14, now: nu), 14)
        XCTAssertFalse(ReadLater.isInWarningWindow(item, termDays: 14, now: nu.addingTimeInterval(11 * dag)))
        // Nog 30 uur: naar boven afgerond 2 dagen, binnen het venster van 2 dagen.
        let dertigUurVoorEinde = nu.addingTimeInterval(14 * dag - 30 * 3600)
        XCTAssertEqual(ReadLater.daysLeft(item, termDays: 14, now: dertigUurVoorEinde), 2)
        XCTAssertTrue(ReadLater.isInWarningWindow(item, termDays: 14, now: dertigUurVoorEinde))
        XCTAssertFalse(
            ReadLater.isInWarningWindow(item, termDays: 14, now: nu.addingTimeInterval(15 * dag)),
            "Verlopen is geen waarschuwing meer")
    }

    func testTermijnNooitVerloopt() {
        let item = FeedItem(title: "A")
        ReadLater.addToReadLater(item, now: nu)
        XCTAssertNil(ReadLater.expiresAt(item, termDays: 0))
        XCTAssertFalse(ReadLater.isExpired(item, termDays: 0, now: nu.addingTimeInterval(1000 * dag)))
        XCTAssertFalse(ReadLater.isInWarningWindow(item, termDays: 0, now: nu.addingTimeInterval(1000 * dag)))
    }

    func testVerlengenStartDeTermijnOpnieuw() {
        let item = FeedItem(title: "A")
        ReadLater.addToReadLater(item, now: nu)
        let later = nu.addingTimeInterval(13 * dag)
        ReadLater.extend(item, now: later)
        XCTAssertEqual(ReadLater.daysLeft(item, termDays: 14, now: later), 14)
    }

    // MARK: - Opruimen (none / readLater / saved)

    func testOpruimregelsPerStatus() throws {
        let oud = nu.addingTimeInterval(-40 * dag)
        let gewoon = FeedItem(title: "Gewoon oud", pubDate: oud)
        let leesLater = FeedItem(title: "Lees later, oud gepubliceerd", pubDate: oud)
        ReadLater.addToReadLater(leesLater, now: nu.addingTimeInterval(-3 * dag))
        let bewaard = FeedItem(title: "Bewaard, oud", pubDate: oud)
        ReadLater.save(bewaard, now: oud)
        let (feed, context) = feedMet([gewoon, leesLater, bewaard])

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu, readLaterTermDays: 14)
        try context.save()

        XCTAssertEqual(try titels(context), ["Bewaard, oud", "Lees later, oud gepubliceerd"])
        XCTAssertNotNil(leesLater.readLaterAddedAt, "Binnen de termijn blijft het in Lees later")
    }

    func testVerlopenLeesLaterValtTerugOnderDeFeedtermijn() throws {
        let recent = FeedItem(title: "Verlopen, recent gepubliceerd", pubDate: nu.addingTimeInterval(-20 * dag))
        ReadLater.addToReadLater(recent, now: nu.addingTimeInterval(-15 * dag))
        let (feed, context) = feedMet([recent], retentionDays: 30)

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu, readLaterTermDays: 14)
        try context.save()

        XCTAssertEqual(try titels(context), ["Verlopen, recent gepubliceerd"], "Niet direct verwijderd")
        XCTAssertNil(recent.readLaterAddedAt, "Wel uit Lees later")
        XCTAssertEqual(recent.laterStatus, .regular)
    }

    /// Beslissing 1 (#224): de feedtermijn telt vanaf de publicatiedatum. Een oud artikel dat
    /// uit Lees later verloopt, kan daardoor in dezelfde opruimronde verdwijnen. Bewust zo.
    func testVerlopenOudArtikelVerdwijntInDezelfdeOpruimronde() throws {
        let oud = FeedItem(title: "Verlopen, oud gepubliceerd", pubDate: nu.addingTimeInterval(-60 * dag))
        ReadLater.addToReadLater(oud, now: nu.addingTimeInterval(-15 * dag))
        let (feed, context) = feedMet([oud], retentionDays: 30)

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu, readLaterTermDays: 14)
        try context.save()

        XCTAssertEqual(try titels(context), [])
    }

    func testVerlopenGebeurtOokAlsOpruimenUitStaat() throws {
        let item = FeedItem(title: "A", pubDate: nu.addingTimeInterval(-60 * dag))
        ReadLater.addToReadLater(item, now: nu.addingTimeInterval(-15 * dag))
        let (feed, context) = feedMet([item], retentionDays: 0)

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu, readLaterTermDays: 14)

        XCTAssertNil(item.readLaterAddedAt)
        XCTAssertEqual(try titels(context), ["A"], "Opruimen staat uit: het artikel blijft")
    }

    func testTermijnNooitWordtNietOpgeruimd() throws {
        let item = FeedItem(title: "A", pubDate: nu.addingTimeInterval(-60 * dag))
        ReadLater.addToReadLater(item, now: nu.addingTimeInterval(-400 * dag))
        let (feed, context) = feedMet([item], retentionDays: 30)

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu, readLaterTermDays: 0)
        try context.save()

        XCTAssertEqual(try titels(context), ["A"])
        XCTAssertNotNil(item.readLaterAddedAt)
    }

    // MARK: - Feed verwijderen

    func testBewaardOverleeftHetVerwijderenVanDeFeed() throws {
        let bewaard = FeedItem(title: "Bewaard", itemDescription: "<p>Tekst</p>")
        ReadLater.save(bewaard, now: nu)
        let leesLater = FeedItem(title: "Lees later")
        ReadLater.addToReadLater(leesLater, now: nu)
        let gewoon = FeedItem(title: "Gewoon")
        let (feed, context) = feedMet([bewaard, leesLater, gewoon])
        try context.save()

        ReadLater.detachSavedItems(from: feed)
        context.delete(feed)
        try context.save()

        let over = try context.fetch(FetchDescriptor<FeedItem>())
        XCTAssertEqual(over.map(\.title), ["Bewaard"])
        XCTAssertNil(over.first?.feed)
        XCTAssertEqual(over.first?.sourceTitle, "Testfeed", "De bronnaam blijft zichtbaar")
        XCTAssertEqual(over.first?.savedContentHTML, "<p>Tekst</p>", "Offline leesbaar")
    }

    func testUitBewaardHalenVanLosArtikelVerwijdertHet() throws {
        let context = ModelContext(container)
        let item = FeedItem(title: "Los")
        ReadLater.save(item, now: nu)
        context.insert(item)
        try context.save()

        ReadLater.unsave(item, context: context)
        try context.save()

        XCTAssertEqual(try titels(context), [], "Zonder feed zou het als wees blijven staan")
    }

    // MARK: - Export en import

    func testExportBevatStatusEnImportZetDieTerug() throws {
        let bewaard = FeedItem(title: "Bewaard", link: "https://example.com/b", guid: "b")
        ReadLater.save(bewaard, now: nu)
        bewaard.tags = ["klimaat"]
        let leesLater = FeedItem(title: "Lees later", link: "https://example.com/l", guid: "l")
        ReadLater.addToReadLater(leesLater, now: nu)
        let gewoon = FeedItem(title: "Gewoon", link: "https://example.com/g", guid: "g")
        let (_, bron) = feedMet([bewaard, leesLater, gewoon])

        let data = SavedArticleIO.export([bewaard, leesLater, gewoon])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"status\" : \"saved\""))
        XCTAssertTrue(json.contains("\"status\" : \"readLater\""))
        XCTAssertFalse(json.contains("Gewoon"), "Gewone artikelen gaan niet mee")
        _ = bron

        let doel = ModelContext(
            try ModelContainer(
                for: Feed.self, FeedItem.self, FeedFolder.self, Topic.self,
                TopicSummary.self, FactCheckResult.self, MastodonAccount.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        XCTAssertEqual(SavedArticleIO.importArticles(from: data, context: doel), 2)
        let items = Dictionary(
            uniqueKeysWithValues: try doel.fetch(FetchDescriptor<FeedItem>()).map { ($0.title, $0) })
        XCTAssertEqual(items["Bewaard"]?.laterStatus, .saved)
        XCTAssertEqual(items["Bewaard"]?.savedAt, nu)
        XCTAssertEqual(items["Bewaard"]?.effectiveTags, ["klimaat"])
        XCTAssertEqual(items["Lees later"]?.laterStatus, .readLater)
        XCTAssertEqual(items["Lees later"]?.readLaterAddedAt, nu)
    }

    func testOudExportbestandImporteertAlsBewaard() throws {
        // Formaat van #220/#223: zonder status-veld.
        let oud = """
            [{"title":"Uit oude export","link":"https://example.com/x","guid":"x","tags":[],
              "feedTitle":"Oude feed","feedURL":"https://example.com/oud.xml"}]
            """
        let context = ModelContext(container)
        XCTAssertEqual(SavedArticleIO.importArticles(from: Data(oud.utf8), context: context), 1)
        let item = try XCTUnwrap(try context.fetch(FetchDescriptor<FeedItem>()).first)
        XCTAssertEqual(item.laterStatus, .saved)
        XCTAssertEqual(item.sourceTitle, "Oude feed")
    }
}
