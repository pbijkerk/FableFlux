//
//  RustigLezenTests.swift
//  FableFluxTests
//

import XCTest

@testable import FableFlux

/// Leesscherm "Rustig lezen" en de contextlaag (#226).
@MainActor
final class RustigLezenTests: XCTestCase {

    // MARK: - Tekstkolom

    func testKolomInTekensEnRegelafstand() {
        let html = ArticleHTMLBuilder.build(content: "<p>Tekst</p>", title: "Titel", feedName: "Bron", date: nil)
        XCTAssertTrue(html.contains("max-width: 56ch;"), "Kolom schaalt mee met de lettergrootte")
        XCTAssertFalse(html.contains("max-width: 680px"))
        XCTAssertTrue(html.contains("line-height: 1.5;"))
    }

    // MARK: - Hoofdfoto

    func testHoofdfotoMetBijschriftEnFotobron() {
        let figuur = ArticleHTMLBuilder.heroFigure(
            url: "https://cdn.example.com/foto.jpg", caption: "Demonstranten op het Malieveld",
            credit: "ANP", content: "<p>Tekst</p>")
        XCTAssertTrue(figuur.contains("<figure class=\"hero\">"))
        XCTAssertTrue(figuur.contains("src=\"https://cdn.example.com/foto.jpg\""))
        XCTAssertTrue(figuur.contains("<span>Demonstranten op het Malieveld</span>"))
        XCTAssertTrue(figuur.contains("Foto: ANP"))
        XCTAssertTrue(figuur.contains("alt=\"Demonstranten op het Malieveld\""), "VoiceOver leest het bijschrift")
    }

    func testHoofdfotoZonderBijschriftHeeftGeenLeegFigcaption() {
        let figuur = ArticleHTMLBuilder.heroFigure(
            url: "https://cdn.example.com/foto.jpg", caption: nil, credit: nil, content: "")
        XCTAssertFalse(figuur.contains("figcaption"))
    }

    func testGeenAfbeeldingGeenLeegVlak() {
        XCTAssertEqual(ArticleHTMLBuilder.heroFigure(url: nil, caption: "x", credit: "y", content: ""), "")
        let html = ArticleHTMLBuilder.build(content: "<p>Tekst</p>", title: "T", feedName: nil, date: nil)
        XCTAssertFalse(html.contains("<figure class=\"hero\""))
    }

    func testFotoDieAlInDeTekstStaatKomtNietDubbel() {
        let content = #"<p><img src="https://cdn.example.com/2026/11/foto.jpg?w=800"></p>"#
        XCTAssertEqual(
            ArticleHTMLBuilder.heroFigure(
                url: "https://cdn.example.com/2026/11/foto.jpg?w=1200", caption: nil, credit: nil, content: content),
            "")
    }

    func testLeestijd() {
        let kort = "<p>" + Array(repeating: "woord", count: 60).joined(separator: " ") + "</p>"
        let lang = "<p>" + Array(repeating: "woord", count: 2300).joined(separator: " ") + "</p>"
        XCTAssertEqual(ArticleHTMLBuilder.readingMinutes(forHTML: kort), 1)
        XCTAssertEqual(ArticleHTMLBuilder.readingMinutes(forHTML: lang), 10)
        let html = ArticleHTMLBuilder.build(content: lang, title: "T", feedName: nil, date: nil, readingMinutes: 10)
        XCTAssertTrue(html.contains("10 min leestijd"))
    }

    // MARK: - Bijschrift en fotobron uit de feed

    func testParserLeestMediaCreditEnBeschrijving() {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>K</title>
              <item>
                <title>Artikel</title>
                <description>De inleiding van het artikel.</description>
                <media:content url="https://cdn.example.com/a.jpg" medium="image">
                  <media:description>Demonstranten op het Malieveld</media:description>
                  <media:credit>ANP / Remko de Waal</media:credit>
                </media:content>
              </item>
            </channel></rss>
            """
        let item = try? XCTUnwrap(RSSParser().parse(data: Data(xml.utf8)).items.first)
        XCTAssertEqual(item?.imageURL, "https://cdn.example.com/a.jpg")
        XCTAssertEqual(item?.imageCaption, "Demonstranten op het Malieveld")
        XCTAssertEqual(item?.imageCredit, "ANP / Remko de Waal")
        XCTAssertEqual(item?.description, "De inleiding van het artikel.", "De artikeltekst blijft ongemoeid")
    }

    func testMediaDescriptionBuitenDeAfbeeldingIsGeenBijschrift() {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>K</title>
              <item><title>A</title><media:description>Over de aflevering</media:description></item>
            </channel></rss>
            """
        XCTAssertNil(RSSParser().parse(data: Data(xml.utf8)).items.first?.imageCaption)
    }

    // MARK: - Contextlaag

    func testLipjeAlleenMetVerhaalgroepOfFactcheck() {
        XCTAssertNil(ArticleContextSheet.lipLabel(relatedCount: 0, hasFactCheck: false), "Geen sheet zonder context")
        XCTAssertEqual(ArticleContextSheet.lipLabel(relatedCount: 4, hasFactCheck: false), "Context · 4 bronnen")
        XCTAssertEqual(ArticleContextSheet.lipLabel(relatedCount: 0, hasFactCheck: true), "Context · factcheck")
        XCTAssertEqual(
            ArticleContextSheet.lipLabel(relatedCount: 3, hasFactCheck: true), "Context · 3 bronnen · factcheck")
    }

    func testAndereBronnenUitDezelfdeCluster() {
        let nos = Feed(url: "https://nos.nl/rss", title: "NOS")
        let nu = Feed(url: "https://nu.nl/rss", title: "NU.nl")
        let nrc = Feed(url: "https://nrc.nl/rss", title: "NRC")
        let datum = Date()
        func artikel(_ titel: String, _ feed: Feed) -> FeedItem {
            let item = FeedItem(title: titel, pubDate: datum)
            item.feed = feed
            return item
        }
        let eigen = artikel("Kabinet presenteert miljoenennota met forse bezuinigingen", nos)
        let ander = artikel("Miljoenennota: kabinet kondigt forse bezuinigingen aan", nu)
        let derde = artikel("Forse bezuinigingen in miljoenennota van kabinet", nrc)
        let losstaand = artikel("Voetbalclub wint bekerfinale na strafschoppen", nrc)

        let clusters = EventClusteringService.shared.cluster(items: [eigen, ander, derde, losstaand])
        let gerelateerd = StoryContext.related(to: eigen, in: clusters)
        XCTAssertEqual(Set(gerelateerd.map(\.title)), [ander.title, derde.title])
        XCTAssertTrue(StoryContext.related(to: losstaand, in: clusters).isEmpty, "Geen verhaalgroep: geen lipje")
    }
}
