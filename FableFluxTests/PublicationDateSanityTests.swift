//
//  PublicationDateSanityTests.swift
//  FableFluxTests
//

import SwiftData
import XCTest

@testable import FableFlux

/// Toetst dat een publicatiedatum ver in de toekomst wordt geweigerd (#103).
///
/// Zo'n datum is niet alleen verkeerd, hij blijft ook hangen: het artikel sorteert bovenaan,
/// valt binnen elk samenvattingsvenster en wordt door de bewaarperiode nooit opgeruimd —
/// het komt dus na elke verversing terug.
@MainActor
final class PublicationDateSanityTests: XCTestCase {

    private var container: ModelContainer!
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)

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

    // MARK: - De grens

    func testEenDatumVanVandaagIsGeloofwaardig() {
        XCTAssertTrue(RSSParser.isPlausiblePublicationDate(nu, now: nu))
    }

    func testEenDatumInHetVerledenBlijftGeloofwaardig() {
        let vorigJaar = nu.addingTimeInterval(-365 * 24 * 3600)
        XCTAssertTrue(
            RSSParser.isPlausiblePublicationDate(vorigJaar, now: nu),
            "Datums in het verleden corrigeren zichzelf en horen ongemoeid te blijven")
    }

    /// Een uitgever met een scheve klok of een verkeerd opgegeven tijdzone scheelt uren,
    /// geen dagen. Binnen de speling blijft de datum staan.
    func testEenPaarUurVoorlopenMag() {
        let straks = nu.addingTimeInterval(6 * 3600)
        XCTAssertTrue(RSSParser.isPlausiblePublicationDate(straks, now: nu))
    }

    func testVerderDanDeSpelingIsOngeloofwaardig() {
        let overtweeDagen = nu.addingTimeInterval(48 * 3600)
        XCTAssertFalse(RSSParser.isPlausiblePublicationDate(overtweeDagen, now: nu))
        XCTAssertEqual(AppConfiguration.maxFutureDateSkew, 24 * 3600)
    }

    /// Het gemelde geval: "in 899 years".
    func testEeuwenInDeToekomstIsOngeloofwaardig() throws {
        let component = DateComponents(year: 2925, month: 9, day: 15)
        let ver = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: component))
        XCTAssertFalse(RSSParser.isPlausiblePublicationDate(ver, now: nu))
    }

    // MARK: - De parser

    func testEenOnwaarschijnlijkeDatumLevertGeenDatumOp() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Kanaal</title>
              <item><title>Ver weg</title><pubDate>2925-09-15</pubDate></item>
            </channel></rss>
            """
        let feed = RSSParser().parse(data: Data(xml.utf8))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertNil(
            item.pubDate,
            "Liever geen datum dan een verzonnen datum: het artikel valt dan terug op fetchedAt")
    }

    func testEenGewoneDatumWordtGewoonGelezen() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Kanaal</title>
              <item><title>Normaal</title><pubDate>Mon, 15 Sep 2025 07:16:00 +0200</pubDate></item>
            </channel></rss>
            """
        let feed = RSSParser().parse(data: Data(xml.utf8))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertNotNil(item.pubDate)
    }

    /// Een `<updated>` dat niet te lezen is mag een wél gelezen `<published>` niet wissen.
    func testEenOnleesbareUpdatedWistDePublishedNiet() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom"><title>Kanaal</title>
              <entry>
                <title>Atom</title>
                <published>2025-09-15T07:16:00Z</published>
                <updated>onzin</updated>
              </entry>
            </feed>
            """
        let feed = RSSParser().parse(data: Data(xml.utf8))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertNotNil(item.pubDate, "De gelezen publicatiedatum hoort te blijven staan")
    }

    // MARK: - Bestaande rijen

    func testBestaandeRijMetToekomstdatumWordtGewist() throws {
        let context = container.mainContext
        let feed = Feed(url: "https://example.com/rss", title: "Testfeed")
        context.insert(feed)

        let ver = FeedItem(title: "Ver weg", pubDate: nu.addingTimeInterval(899 * 365 * 24 * 3600))
        let gewoon = FeedItem(title: "Gewoon", pubDate: nu.addingTimeInterval(-3600))
        for item in [ver, gewoon] {
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
        }

        FeedRefreshService.clearImplausibleDates(feed: feed, context: context, now: nu)

        XCTAssertNil(ver.pubDate, "De onwaarschijnlijke datum hoort gewist te zijn")
        XCTAssertNotNil(ver.fetchedAt, "Zonder pubDate moet fetchedAt de klok leveren")
        XCTAssertEqual(gewoon.pubDate, nu.addingTimeInterval(-3600), "De rest blijft ongemoeid")
        XCTAssertEqual(feed.items.count, 2, "Er wordt niets verwijderd, alleen gecorrigeerd")
    }

    /// Het gemelde gedrag: zo'n artikel viel binnen elk samenvattingsvenster. Na het wissen
    /// gedraagt het zich naar het moment van ophalen.
    func testNaHetWissenGeldtHetOphaalmomentVoorDeSamenvatting() throws {
        let context = container.mainContext
        let feed = Feed(url: "https://example.com/rss", title: "Testfeed")
        context.insert(feed)

        let ver = FeedItem(title: "Ver weg", pubDate: nu.addingTimeInterval(899 * 365 * 24 * 3600))
        ver.fetchedAt = nu.addingTimeInterval(-72 * 3600)
        ver.feed = feed
        feed.items.append(ver)
        context.insert(ver)

        XCTAssertFalse(
            TopicClusteringService.withinSummaryWindow([ver], now: nu).isEmpty,
            "Vóór de correctie valt het artikel binnen elk venster")

        FeedRefreshService.clearImplausibleDates(feed: feed, context: context, now: nu)

        XCTAssertTrue(
            TopicClusteringService.withinSummaryWindow([ver], now: nu).isEmpty,
            "Daarna telt het ophaalmoment, en dat ligt buiten het venster van 48 uur")
    }
}
