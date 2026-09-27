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

    // MARK: - Favoriet = voorrang (#154)

    /// Voegt artikelen met de opgegeven titels toe aan één testfeed.
    private func makeItems(titles: [String]) -> [FeedItem] {
        let context = container.mainContext
        let feed = Feed(url: "https://example.com/favorieten.rss", title: "Favorietenfeed")
        context.insert(feed)

        return titles.enumerated().map { index, title in
            let item = FeedItem(
                title: title,
                itemDescription: nil,
                pubDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600)
            )
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
            return item
        }
    }

    /// Clustert met één favoriet ("Zeppelin", één artikel) en één niet-favoriet
    /// eigen onderwerp ("Kaas", drie artikelen), plus één artikel dat alleen op een
    /// standaardonderwerp (Politics, trefwoord "election") past.
    private func clusterMetFavoriet() async throws -> [TopicCluster] {
        let items = makeItems(titles: [
            "Zeppelin landt",
            "Kaas uit Gouda",
            "Kaas uit Edam",
            "Kaas uit Leiden",
            "Verkiezingen: de election is begonnen",
        ])
        let favoriet = Topic(name: "Zeppelin", keywords: ["zeppelin"], isLiked: true)
        let gewoon = Topic(name: "Kaas", keywords: ["kaas"], isLiked: false)
        container.mainContext.insert(favoriet)
        container.mainContext.insert(gewoon)

        let service = TopicClusteringService()
        let resultaat = await service.cluster(items: items, savedTopics: [favoriet, gewoon], claudeAPIKey: nil)
        return try XCTUnwrap(resultaat)
    }

    func testFavorietFiltertAndereOnderwerpenNietWegEnStaatEerst() async throws {
        let clusters = try await clusterMetFavoriet()
        let namen = clusters.map(\.topicName)

        XCTAssertTrue(namen.contains("Zeppelin"), "Het favoriete onderwerp hoort een cluster te hebben")
        XCTAssertTrue(namen.contains("Kaas"), "Een niet-favoriet eigen onderwerp hoort ook mee te doen")
        XCTAssertEqual(
            namen.first, "Zeppelin",
            "De favoriet hoort bovenaan te staan, ook met minder artikelen")

        let kaas = try XCTUnwrap(clusters.first { $0.topicName == "Kaas" })
        XCTAssertEqual(kaas.items.count, 3)
    }

    func testStandaardonderwerpenDoenMeeNaastEenFavoriet() async throws {
        let clusters = try await clusterMetFavoriet()

        let politiek = try XCTUnwrap(
            clusters.first { $0.topicName == "Politics" },
            "Met een favoriet horen de standaardonderwerpen nog mee te doen")
        XCTAssertEqual(politiek.items.map(\.title), ["Verkiezingen: de election is begonnen"])
    }

    func testIsFavorietAlleenVoorFavorieteOnderwerpen() async throws {
        let clusters = try await clusterMetFavoriet()

        for cluster in clusters {
            XCTAssertEqual(
                cluster.isFavorite, cluster.topicName == "Zeppelin",
                "isFavorite klopt niet voor \(cluster.topicName)")
        }
        XCTAssertEqual(clusters.filter(\.isFavorite).count, 1)
    }

    /// Binnen de groep favorieten en binnen de rest blijft de sortering op aantal
    /// artikelen, aflopend.
    func testSorteringBinnenGroepenOpAantalArtikelen() async throws {
        let items = makeItems(titles: [
            "Zeppelin landt",
            "Ballon stijgt",
            "Ballon daalt",
            "Kaas uit Gouda",
            "Worst uit Gelderland",
            "Worst uit Brabant",
        ])
        let topics = [
            Topic(name: "Zeppelin", keywords: ["zeppelin"], isLiked: true),
            Topic(name: "Ballon", keywords: ["ballon"], isLiked: true),
            Topic(name: "Kaas", keywords: ["kaas"], isLiked: false),
            Topic(name: "Worst", keywords: ["worst"], isLiked: false),
        ]
        for topic in topics { container.mainContext.insert(topic) }

        let service = TopicClusteringService()
        let resultaat = await service.cluster(items: items, savedTopics: topics, claudeAPIKey: nil)
        let clusters = try XCTUnwrap(resultaat)

        XCTAssertEqual(clusters.map(\.topicName), ["Ballon", "Zeppelin", "Worst", "Kaas"])
    }

    // MARK: - Nederlandse onderwerpen (#155)

    /// Clustert de titels zonder opgeslagen onderwerpen, dus alleen op de standaardonderwerpen,
    /// en levert per titel de (Engelse) sleutel van het cluster waarin hij terechtkwam.
    private func standaardonderwerp(voor titles: [String]) async throws -> [String: String] {
        let items = makeItems(titles: titles)
        let service = TopicClusteringService()
        let resultaat = await service.cluster(items: items, savedTopics: [], claudeAPIKey: nil)
        let clusters = try XCTUnwrap(resultaat)

        var onderwerpPerTitel: [String: String] = [:]
        for cluster in clusters {
            for item in cluster.items { onderwerpPerTitel[item.title] = cluster.topicName }
        }
        return onderwerpPerTitel
    }

    func testNederlandseArtikelenKomenInHetJuisteStandaardonderwerp() async throws {
        let onderwerpen = try await standaardonderwerp(voor: [
            "Kabinet valt na stemming in de Tweede Kamer",
            "Ajax wint van PSV in de eredivisie",
            "Ziekenhuizen kampen met tekort aan verpleegkundigen",
        ])

        XCTAssertEqual(onderwerpen["Kabinet valt na stemming in de Tweede Kamer"], "Politics")
        XCTAssertEqual(onderwerpen["Ajax wint van PSV in de eredivisie"], "Sports")
        XCTAssertEqual(onderwerpen["Ziekenhuizen kampen met tekort aan verpleegkundigen"], "Health")
    }

    func testEngelsArtikelBlijftHetzelfdeIngedeeld() async throws {
        let titel = "Stock market rallies as investors cheer record profit"
        let onderwerpen = try await standaardonderwerp(voor: [titel])

        XCTAssertEqual(onderwerpen[titel], "Business")
    }

    func testWeergavenaamVolgtDeSamenvattingstaal() {
        XCTAssertEqual(TopicCluster.displayName(for: "Politics", language: "nl"), "Politiek")
        XCTAssertEqual(TopicCluster.displayName(for: "Politics", language: "en"), "Politics")
        XCTAssertEqual(TopicCluster.displayName(for: "Entertainment", language: "nl"), "Cultuur & media")
        XCTAssertEqual(
            TopicCluster.displayName(for: "politics", language: "nl"), "Politiek",
            "Een opgeslagen onderwerp met afwijkende hoofdletters hoort ook vertaald te worden")
    }

    func testEigenOnderwerpHoudtZijnEigenNaam() {
        XCTAssertEqual(TopicCluster.displayName(for: "Klimaat", language: "nl"), "Klimaat")
        XCTAssertEqual(TopicCluster.displayName(for: "Klimaat", language: "en"), "Klimaat")
    }

    /// De sleutel blijft Engels: daarop rusten identiteit, kleur en opslag van het onderwerp.
    func testTopicNameBlijftDeEngelseSleutel() async throws {
        let items = makeItems(titles: ["Kabinet valt na stemming in de Tweede Kamer"])
        let service = TopicClusteringService()
        let resultaat = await service.cluster(items: items, savedTopics: [], claudeAPIKey: nil)
        let clusters = try XCTUnwrap(resultaat)

        XCTAssertEqual(clusters.map(\.topicName), ["Politics"])
    }
}
