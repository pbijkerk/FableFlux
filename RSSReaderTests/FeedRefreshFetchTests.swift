//
//  FeedRefreshFetchTests.swift
//  RSSReaderTests
//

import SwiftData
import XCTest

@testable import RSSReader

/// Toetst dat verversen met gebundelde queries hetzelfde doet als voorheen (#119):
/// dubbelen herkennen op guid, dan link, dan titel; en alleen de artikelen van de eigen
/// feed meetellen. Elke test laadt de feed in een verse context, zodat de artikelen echt
/// uit de store komen en niet uit het geheugen van de context die ze aanmaakte.
@MainActor
final class FeedRefreshFetchTests: XCTestCase {

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

    /// Slaat een feed met artikelen op en geeft hem terug uit een nieuwe context.
    private func opgeslagenFeed(
        url: String = "https://example.com/rss",
        items: [FeedItem]
    ) throws -> (Feed, ModelContext) {
        let schrijf = ModelContext(container)
        let feed = Feed(url: url, title: "Testfeed")
        schrijf.insert(feed)
        for item in items {
            item.feed = feed
            feed.items.append(item)
            schrijf.insert(item)
        }
        try schrijf.save()

        let lees = ModelContext(container)
        let feedID = feed.id
        let geladen = try XCTUnwrap(
            lees.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedID })).first
        )
        return (geladen, lees)
    }

    private func titels(_ feed: Feed, _ context: ModelContext) throws -> [String] {
        let feedID = feed.id
        let items = try context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.feed?.id == feedID }))
        return items.map(\.title).sorted()
    }

    // MARK: - Dubbelcontrole

    func testBestaandeArtikelenWordenHerkendOpGuidLinkEnTitel() throws {
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Met guid", link: "https://example.com/a", guid: "guid-a"),
            FeedItem(title: "Alleen link", link: "https://example.com/b"),
            FeedItem(title: "Alleen titel"),
        ])

        var parsed = ParsedFeed()
        parsed.items = [
            // Zelfde guid, andere titel: blijft een dubbel.
            ParsedFeedItem(title: "Met guid (bijgewerkt)", link: "https://example.com/a", guid: "guid-a"),
            ParsedFeedItem(title: "Alleen link", link: "https://example.com/b"),
            ParsedFeedItem(title: "Alleen titel"),
            ParsedFeedItem(title: "Nieuw", link: "https://example.com/c", guid: "guid-c"),
        ]

        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Alleen link", "Alleen titel", "Met guid", "Nieuw"])
    }

    func testArtikelenVanAndereFeedsTellenNietMee() throws {
        _ = try opgeslagenFeed(
            url: "https://ander.example.com/rss",
            items: [FeedItem(title: "Gedeeld", guid: "guid-gedeeld")]
        )
        let (feed, context) = try opgeslagenFeed(items: [])

        var parsed = ParsedFeed()
        parsed.items = [ParsedFeedItem(title: "Gedeeld", guid: "guid-gedeeld")]

        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Gedeeld"])
    }

    func testTweemaalVerversenLevertGeenDubbelen() throws {
        let (feed, context) = try opgeslagenFeed(items: [])
        var parsed = ParsedFeed()
        parsed.items = [
            ParsedFeedItem(title: "Een", guid: "1"),
            ParsedFeedItem(title: "Twee", link: "https://example.com/2"),
        ]

        let service = FeedRefreshService()
        service.applyParsedFeed(parsed, to: feed, context: context)
        try context.save()
        service.applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Een", "Twee"])
    }

    // MARK: - Wisselende guid-fragmenten (#135)

    /// Het BBC-patroon: hetzelfde artikel twee keer in één feed, met `#1` en `#9`.
    func testZelfdeArtikelMetAnderGuidFragmentKomtEenKeerBinnen() throws {
        let (feed, context) = try opgeslagenFeed(items: [])
        let link = "https://www.bbc.co.uk/sport/football/articles/cwywld5v28jo?at_medium=RSS"
        var parsed = ParsedFeed()
        parsed.items = [
            ParsedFeedItem(
                title: "Hacker", link: link, guid: "https://www.bbc.co.uk/sport/football/articles/cwywld5v28jo#1"),
            ParsedFeedItem(
                title: "Hacker", link: link, guid: "https://www.bbc.co.uk/sport/football/articles/cwywld5v28jo#9"),
        ]

        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Hacker"])
    }

    /// Later in de dag draagt hetzelfde artikel een ander fragment.
    func testAnderGuidFragmentBijEenLatereVerversingIsEenDubbel() throws {
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Hacker", guid: "https://www.bbc.co.uk/sport/football/articles/cwywld5v28jo#1")
        ])
        var parsed = ParsedFeed()
        parsed.items = [
            ParsedFeedItem(title: "Hacker", guid: "https://www.bbc.co.uk/sport/football/articles/cwywld5v28jo#3")
        ]

        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Hacker"])
    }

    /// Podcastfeeds geven elk item vaak dezelfde link; afleveringen onderscheiden zich
    /// alleen op guid. Die mogen niet als dubbel worden gezien.
    func testAfleveringenMetDezelfdeLinkKomenAllemaalBinnen() throws {
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Aflevering 1", link: "https://podcast.example.com", guid: "ep-1")
        ])
        var parsed = ParsedFeed()
        parsed.items = [
            ParsedFeedItem(title: "Aflevering 1", link: "https://podcast.example.com", guid: "ep-1"),
            ParsedFeedItem(title: "Aflevering 2", link: "https://podcast.example.com", guid: "ep-2"),
            ParsedFeedItem(title: "Aflevering 3", link: "https://podcast.example.com", guid: "ep-3"),
        ]

        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Aflevering 1", "Aflevering 2", "Aflevering 3"])
    }

    func testGuidSleutel() {
        XCTAssertEqual(
            FeedRefreshService.guidKey("https://www.bbc.co.uk/news/articles/abc#9"),
            "https://www.bbc.co.uk/news/articles/abc")
        XCTAssertEqual(FeedRefreshService.guidKey("https://example.com/a"), "https://example.com/a")
        // Geen URL: een # hoort dan bij de id zelf.
        XCTAssertEqual(FeedRefreshService.guidKey("tag:example.com,2026:post#1"), "tag:example.com,2026:post#1")
        XCTAssertEqual(FeedRefreshService.guidKey("ep-1"), "ep-1")
    }

    // MARK: - Opruimen en datumherstel uit de store

    func testOpruimenUitDeStoreRespecteertBewaardEnDatum() throws {
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Oud", pubDate: nu.addingTimeInterval(-40 * 24 * 3600)),
            FeedItem(title: "Oud zonder pubDate", pubDate: nil, fetchedAt: nu.addingTimeInterval(-40 * 24 * 3600)),
            FeedItem(
                title: "Oud gepubliceerd, vers opgehaald", pubDate: nu.addingTimeInterval(-40 * 24 * 3600),
                fetchedAt: nu),
            FeedItem(title: "Vers", pubDate: nu.addingTimeInterval(-3600)),
            FeedItem(title: "Rij van vóór #89", pubDate: nil, fetchedAt: nil),
            {
                let item = FeedItem(title: "Oud en bewaard", pubDate: nu.addingTimeInterval(-40 * 24 * 3600))
                item.isSaved = true
                return item
            }(),
        ])
        feed.retentionDays = 30

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu)
        XCTAssertEqual(
            feed.items.map(\.title).sorted(),
            ["Oud en bewaard", "Rij van vóór #89", "Vers"],
            "Ook de relatie in het geheugen hoort bij te zijn")
        try context.save()

        XCTAssertEqual(try titels(feed, context), ["Oud en bewaard", "Rij van vóór #89", "Vers"])
    }

    func testDatumherstelUitDeStoreRaaktAlleenOnwaarschijnlijkeDatums() throws {
        let ver = nu.addingTimeInterval(899 * 365 * 24 * 3600)
        let netBinnenSpeling = nu.addingTimeInterval(AppConfiguration.maxFutureDateSkew - 60)
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Ver weg", pubDate: ver, fetchedAt: nil),
            FeedItem(title: "Net binnen de speling", pubDate: netBinnenSpeling),
            FeedItem(title: "Gewoon", pubDate: nu.addingTimeInterval(-3600)),
        ])

        FeedRefreshService.clearImplausibleDates(feed: feed, context: context, now: nu)
        try context.save()

        let items = Dictionary(uniqueKeysWithValues: feed.items.map { ($0.title, $0) })
        XCTAssertNil(items["Ver weg"]?.pubDate)
        XCTAssertEqual(items["Ver weg"]?.fetchedAt, nu)
        XCTAssertEqual(items["Net binnen de speling"]?.pubDate, netBinnenSpeling)
        XCTAssertEqual(items["Gewoon"]?.pubDate, nu.addingTimeInterval(-3600))
    }

    // MARK: - Waarnemers van feed.items

    /// Schermen als `FeedItemsView` tonen `feed.items` en tekenen alleen opnieuw als die
    /// relatie wijzigt. Alleen `item.feed` zetten werkt de data bij maar geeft geen seintje.
    func testNieuweArtikelenMeldenZichBijWaarnemersVanFeedItems() throws {
        let (feed, context) = try opgeslagenFeed(items: [FeedItem(title: "Bestaand", guid: "b")])
        var gewijzigd = false
        withObservationTracking {
            _ = feed.items.count
        } onChange: {
            gewijzigd = true
        }

        var parsed = ParsedFeed()
        parsed.items = [ParsedFeedItem(title: "Nieuw", guid: "n")]
        FeedRefreshService().applyParsedFeed(parsed, to: feed, context: context)

        XCTAssertTrue(gewijzigd)
        XCTAssertEqual(feed.items.count, 2)
    }

    func testOpruimenMeldtZichBijWaarnemersVanFeedItems() throws {
        let (feed, context) = try opgeslagenFeed(items: [
            FeedItem(title: "Oud", pubDate: nu.addingTimeInterval(-90 * 24 * 3600))
        ])
        feed.retentionDays = 7
        var gewijzigd = false
        withObservationTracking {
            _ = feed.items.count
        } onChange: {
            gewijzigd = true
        }

        FeedRefreshService.pruneOldItems(feed: feed, context: context, now: nu)

        XCTAssertTrue(gewijzigd)
        XCTAssertTrue(feed.items.isEmpty)
    }
}
