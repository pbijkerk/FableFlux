//
//  TopicClusteringOrderTests.swift
//  FableFluxTests
//

import SwiftData
import XCTest

@testable import FableFlux

/// Legt vast dat de samenvatting op de **nieuwste** artikelen wordt gebaseerd (#65).
/// `generateSummaryWithClaude` en `localSummary` knippen allebei met `prefix(...)`;
/// zonder sortering vooraf is dat de volgorde waarin artikelen ooit zijn opgeslagen,
/// waardoor nieuwe artikelen bij een vol onderwerp nooit in de prompt belanden.
///
/// Draait zonder API-sleutel, dus via `localSummary`: die maakt één bewering per
/// artikel, in dezelfde volgorde, wat de volgorde toetsbaar maakt zonder netwerk.
@MainActor
final class TopicClusteringOrderTests: XCTestCase {

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

    /// Bouwt `count` artikelen die allemaal op het onderwerp matchen, oplopend in tijd:
    /// index 0 is het oudst, index `count - 1` het nieuwst. Ze worden bewust in die
    /// oude-eerst-volgorde ingevoegd, want dat is precies de situatie waarin de bug zich
    /// voordeed.
    private func makeItems(count: Int) -> [FeedItem] {
        let context = container.mainContext
        let feed = Feed(url: "https://example.com/rss", title: "Testfeed")
        context.insert(feed)

        var items: [FeedItem] = []
        for index in 0..<count {
            let item = FeedItem(
                title: "Zeppelin nieuws \(index)",
                itemDescription: "Bericht over de zeppelin, nummer \(index).",
                pubDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600)
            )
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
            items.append(item)
        }
        return items
    }

    private func clusterZeppelin(items: [FeedItem]) async -> TopicCluster? {
        let topic = Topic(name: "Zeppelin", keywords: ["zeppelin"], isLiked: true)
        container.mainContext.insert(topic)

        let service = TopicClusteringService()
        let result = await service.cluster(items: items, savedTopics: [topic], claudeAPIKey: nil)
        return result?.first { $0.topicName == "Zeppelin" }
    }

    func testArtikelenStaanNieuwsteEerst() async throws {
        let items = makeItems(count: 12)
        let resultaat = await clusterZeppelin(items: items)
        let cluster = try XCTUnwrap(resultaat)

        XCTAssertEqual(cluster.items.count, 12)
        XCTAssertEqual(
            cluster.items.map(\.id), items.reversed().map(\.id),
            "Het cluster hoort de artikelen nieuwste-eerst te bevatten")
    }

    /// De kern van #65: de beweringen moeten uit de nieuwste artikelen komen, niet uit
    /// de eerst opgeslagen. `localSummary` maakt één bewering per artikel in volgorde,
    /// dus de bronnen van de beweringen horen de eerste N nieuwste artikelen te zijn.
    func testSamenvattingGebruiktDeNieuwsteArtikelen() async throws {
        let items = makeItems(count: 12)
        let resultaat = await clusterZeppelin(items: items)
        let cluster = try XCTUnwrap(resultaat)

        let gebruikteIDs = cluster.statements.flatMap(\.sourceItemIDs)
        XCTAssertFalse(gebruikteIDs.isEmpty, "Er hoort minstens één bewering te zijn")

        let nieuwsteEerst = items.reversed().map(\.id)
        XCTAssertEqual(
            gebruikteIDs, Array(nieuwsteEerst.prefix(gebruikteIDs.count)),
            "De beweringen horen op de nieuwste artikelen te steunen, in die volgorde")

        let oudsteID = try XCTUnwrap(items.first?.id)
        XCTAssertFalse(
            gebruikteIDs.contains(oudsteID),
            "Het oudste artikel hoort niet in de samenvatting terwijl er elf nieuwere zijn")
    }

    /// Een nieuw artikel hoort de samenvatting te veranderen — precies wat #65 meldde
    /// dat niet gebeurde.
    func testEenNieuwerArtikelVerandertDeSamenvatting() async throws {
        let items = makeItems(count: 12)
        let eersteResultaat = await clusterZeppelin(items: items)
        let eerste = try XCTUnwrap(eersteResultaat)
        let voorIDs = eerste.statements.flatMap(\.sourceItemIDs)

        let context = container.mainContext
        let feed = try XCTUnwrap(items.first?.feed)
        let nieuwste = FeedItem(
            title: "Zeppelin nieuws vers",
            itemDescription: "Het allerlaatste bericht over de zeppelin.",
            pubDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        nieuwste.feed = feed
        feed.items.append(nieuwste)
        context.insert(nieuwste)

        let tweedeResultaat = await clusterZeppelin(items: items + [nieuwste])
        let tweede = try XCTUnwrap(tweedeResultaat)
        let naIDs = tweede.statements.flatMap(\.sourceItemIDs)

        XCTAssertEqual(
            naIDs.first, nieuwste.id,
            "Het nieuwste artikel hoort de samenvatting aan te voeren")
        XCTAssertNotEqual(voorIDs, naIDs, "De samenvatting hoort te veranderen")
    }

    /// Een artikel zonder `pubDate` mag de sortering niet laten crashen en hoort
    /// achteraan te sorteren, zoals overal elders in de app.
    func testArtikelZonderDatumSorteertAchteraan() async throws {
        let items = makeItems(count: 3)
        let context = container.mainContext
        let feed = try XCTUnwrap(items.first?.feed)

        let zonderDatum = FeedItem(
            title: "Zeppelin zonder datum",
            itemDescription: "Bericht over de zeppelin zonder publicatiedatum.",
            pubDate: nil
        )
        zonderDatum.feed = feed
        feed.items.append(zonderDatum)
        context.insert(zonderDatum)

        let resultaat = await clusterZeppelin(items: [zonderDatum] + items)
        let cluster = try XCTUnwrap(resultaat)

        XCTAssertEqual(cluster.items.count, 4)
        XCTAssertEqual(
            cluster.items.last?.id, zonderDatum.id,
            "Zonder datum hoort het artikel achteraan te staan, niet vooraan")
    }
}
