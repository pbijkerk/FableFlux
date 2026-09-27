//
//  RSSParserTests.swift
//  FableFluxTests
//

import XCTest

@testable import FableFlux

/// Toetst `RSSParser` op gedrag, via `parse(data:)` — niet op interne functies. Alles wat
/// hier staat is pure logica: geen netwerk, geen SwiftData, geen Claude-call.
final class RSSParserTests: XCTestCase {

    private func parse(_ xml: String) -> ParsedFeed {
        RSSParser().parse(data: Data(xml.utf8))
    }

    /// Bouwt een RSS-feed met één item, zodat een test alleen het relevante deel toont.
    private func rss(item: String, channelExtra: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:media="http://search.yahoo.com/mrss/" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel>
          <title>Kanaal</title>
          <description>Omschrijving</description>
          \(channelExtra)
          <item>\(item)</item>
        </channel></rss>
        """
    }

    // MARK: - 1. Basisvelden

    func testRSSItemVeldenWordenGelezen() {
        let feed = parse(
            rss(
                item: """
                    <title>Titel</title>
                    <link>https://example.com/a</link>
                    <description>Tekst</description>
                    <guid>abc-123</guid>
                    """))

        XCTAssertEqual(feed.title, "Kanaal")
        XCTAssertEqual(feed.description, "Omschrijving")
        XCTAssertEqual(feed.items.count, 1)

        XCTAssertEqual(feed.items.first?.title, "Titel")
        XCTAssertEqual(feed.items.first?.link, "https://example.com/a")
        XCTAssertEqual(feed.items.first?.description, "Tekst")
        XCTAssertEqual(feed.items.first?.guid, "abc-123")
    }

    func testAtomEntryWordtGelezen() {
        let feed = parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>Atom-kanaal</title>
              <subtitle>Ondertitel</subtitle>
              <entry>
                <title>Bericht</title>
                <link href="https://example.com/atom"/>
                <summary>Samenvatting</summary>
                <id>urn:uuid:1</id>
              </entry>
            </feed>
            """)

        XCTAssertEqual(feed.title, "Atom-kanaal")
        XCTAssertEqual(feed.description, "Ondertitel")
        XCTAssertEqual(feed.items.first?.title, "Bericht")
        XCTAssertEqual(feed.items.first?.link, "https://example.com/atom")
        XCTAssertEqual(feed.items.first?.description, "Samenvatting")
        XCTAssertEqual(feed.items.first?.guid, "urn:uuid:1")
    }

    func testMeerdereItemsBehoudenHunVolgorde() {
        let feed = parse(
            """
            <rss version="2.0"><channel>
              <title>K</title>
              <item><title>Een</title></item>
              <item><title>Twee</title></item>
              <item><title>Drie</title></item>
            </channel></rss>
            """)

        XCTAssertEqual(feed.items.map(\.title), ["Een", "Twee", "Drie"])
    }

    /// De kanaaltitel wordt één keer gezet. Een `<title>` in bijvoorbeeld `<image>`
    /// mag die niet overschrijven.
    func testKanaaltitelWordtNietOverschrevenDoorEenLaterTitleElement() {
        let feed = parse(
            rss(
                item: "<title>Artikel</title>",
                channelExtra: "<image><title>Logo</title><url>https://example.com/l.png</url></image>"
            ))

        XCTAssertEqual(feed.title, "Kanaal")
    }

    // MARK: - 2. Datums

    func testRFC822DatumMetOffset() {
        let feed = parse(rss(item: "<pubDate>Mon, 08 Sep 2026 14:30:00 +0200</pubDate>"))
        XCTAssertEqual(feed.items.first?.pubDate, Date(timeIntervalSince1970: 1_788_870_600))
    }

    func testISO8601DatumInUTC() {
        let feed = parse(rss(item: "<pubDate>2026-09-08T12:30:00Z</pubDate>"))
        XCTAssertEqual(feed.items.first?.pubDate, Date(timeIntervalSince1970: 1_788_870_600))
    }

    func testISO8601DatumMetMilliseconden() {
        let feed = parse(rss(item: "<pubDate>2026-09-08T12:30:00.000Z</pubDate>"))
        XCTAssertEqual(feed.items.first?.pubDate, Date(timeIntervalSince1970: 1_788_870_600))
    }

    func testDatumZonderTijd() {
        let feed = parse(rss(item: "<pubDate>2026-09-08</pubDate>"))
        XCTAssertNotNil(feed.items.first?.pubDate)
    }

    func testOnleesbareDatumLevertNil() {
        let feed = parse(rss(item: "<pubDate>gisteren</pubDate>"))
        XCTAssertNil(feed.items.first?.pubDate)
    }

    func testAtomPublishedWordtAlsDatumGelezen() {
        let feed = parse(
            """
            <feed><entry><published>2026-09-08T12:30:00Z</published></entry></feed>
            """)
        XCTAssertEqual(feed.items.first?.pubDate, Date(timeIntervalSince1970: 1_788_870_600))
    }

    // MARK: - 3. Mediatype en enclosures

    func testAudioEnclosureMaaktErEenAudiofeedVan() {
        let feed = parse(
            rss(item: #"<enclosure url="https://example.com/a.mp3" type="audio/mpeg"/>"#))

        XCTAssertEqual(feed.detectedMediaType, .audio)
        XCTAssertEqual(feed.items.first?.enclosureURL, "https://example.com/a.mp3")
        XCTAssertEqual(feed.items.first?.enclosureMIMEType, "audio/mpeg")
    }

    func testVideoEnclosureMaaktErEenVideofeedVan() {
        let feed = parse(
            rss(item: #"<enclosure url="https://example.com/v.mp4" type="video/mp4"/>"#))
        XCTAssertEqual(feed.detectedMediaType, .video)
    }

    func testAudioWintVanVideoAlsBeideVoorkomen() {
        let feed = parse(
            """
            <rss version="2.0"><channel><title>K</title>
              <item><enclosure url="https://example.com/v.mp4" type="video/mp4"/></item>
              <item><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/></item>
            </channel></rss>
            """)
        XCTAssertEqual(feed.detectedMediaType, .audio)
    }

    func testAlleenEenAfbeeldingLaatHetMediatypeOnbekend() {
        let feed = parse(
            rss(item: #"<enclosure url="https://example.com/p.jpg" type="image/jpeg"/>"#))

        XCTAssertEqual(feed.detectedMediaType, .unknown)
        XCTAssertEqual(feed.items.first?.imageURL, "https://example.com/p.jpg")
    }

    // MARK: - 4. Afbeeldingen

    func testMediaThumbnailLevertDeAfbeelding() {
        let feed = parse(rss(item: #"<media:thumbnail url="https://example.com/t.jpg"/>"#))
        XCTAssertEqual(feed.items.first?.imageURL, "https://example.com/t.jpg")
    }

    func testMediaContentTeltAlleenMetMediumImage() {
        let metImage = parse(
            rss(item: #"<media:content url="https://example.com/c.jpg" medium="image"/>"#))
        XCTAssertEqual(metImage.items.first?.imageURL, "https://example.com/c.jpg")

        let metVideo = parse(
            rss(item: #"<media:content url="https://example.com/c.mp4" medium="video"/>"#))
        XCTAssertNil(metVideo.items.first?.imageURL)
    }

    func testAfbeeldingUitDeBeschrijvingAlsErGeenExpliciteIs() {
        let feed = parse(
            rss(
                item:
                    #"<description>&lt;p&gt;Tekst&lt;img src="https://example.com/in.jpg"&gt;&lt;/p&gt;</description>"#)
        )
        XCTAssertEqual(feed.items.first?.imageURL, "https://example.com/in.jpg")
    }

    /// Trackingpixels horen niet als artikelafbeelding te eindigen.
    func testTrackingpixelsWordenGenegeerd() {
        let pixels = [
            "https://example.com/1x1.png",
            "https://example.com/pixel.png",
            "https://example.com/tracker.png",
            "https://ex.com/s.gif",
        ]

        for pixel in pixels {
            let feed = parse(
                rss(item: "<description>&lt;img src=\"\(pixel)\"&gt;</description>"))
            XCTAssertNil(
                feed.items.first?.imageURL,
                "\(pixel) hoort niet als artikelafbeelding te worden gebruikt")
        }
    }

    func testExplicieteAfbeeldingWintVanDieUitDeBeschrijving() {
        let feed = parse(
            rss(
                item: """
                    <media:thumbnail url="https://example.com/t.jpg"/>
                    <description>&lt;img src="https://example.com/in.jpg"&gt;</description>
                    """))
        XCTAssertEqual(feed.items.first?.imageURL, "https://example.com/t.jpg")
    }

    // MARK: - 5. Inhoud

    func testCDATAInDeBeschrijvingWordtGelezen() {
        let feed = parse(
            rss(item: "<description><![CDATA[<p>Met <b>opmaak</b></p>]]></description>"))
        XCTAssertEqual(feed.items.first?.description, "<p>Met <b>opmaak</b></p>")
    }

    /// `content:encoded` bevat doorgaans het volledige artikel en wint daarom van
    /// de korte `description`, ongeacht de volgorde in de XML.
    func testContentEncodedWintVanDescription() {
        let feed = parse(
            rss(
                item: """
                    <description>Kort</description>
                    <content:encoded><![CDATA[Volledig artikel]]></content:encoded>
                    """))
        XCTAssertEqual(feed.items.first?.description, "Volledig artikel")
    }

    func testWitruimteRondomTekstWordtWeggehaald() {
        let feed = parse(
            rss(
                item: """
                    <title>
                        Titel met witruimte
                    </title>
                    """))
        XCTAssertEqual(feed.items.first?.title, "Titel met witruimte")
    }

    // MARK: - 6. Randgevallen

    func testLegeDataLevertEenLegeFeed() {
        let feed = RSSParser().parse(data: Data())
        XCTAssertTrue(feed.items.isEmpty)
        XCTAssertEqual(feed.title, "")
        XCTAssertEqual(feed.detectedMediaType, .unknown)
    }

    func testTekstDieGeenXMLIsLevertEenLegeFeed() {
        let feed = parse("dit is geen xml")
        XCTAssertTrue(feed.items.isEmpty)
        XCTAssertEqual(feed.title, "")
    }

    func testFeedZonderItemsLevertGeenItems() {
        let feed = parse(
            """
            <rss version="2.0"><channel>
              <title>Leeg kanaal</title>
              <description>Zonder artikelen</description>
            </channel></rss>
            """)

        XCTAssertEqual(feed.title, "Leeg kanaal")
        XCTAssertTrue(feed.items.isEmpty)
    }

    func testItemZonderVeldenLevertLegeWaardenGeenCrash() {
        let feed = parse(rss(item: ""))

        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items.first?.title, "")
        XCTAssertEqual(feed.items.first?.link, "")
        XCTAssertNil(feed.items.first?.pubDate)
        XCTAssertNil(feed.items.first?.imageURL)
    }

    /// Een parser wordt hergebruikt tussen feeds; de vorige feed mag niet doorlekken.
    func testHergebruikVanDeParserLaatGeenRestenAchter() {
        let parser = RSSParser()
        let eerste = parser.parse(
            data: Data(
                rss(item: #"<title>Een</title><enclosure url="https://e.com/a.mp3" type="audio/mpeg"/>"#)
                    .utf8))
        XCTAssertEqual(eerste.items.count, 1)
        XCTAssertEqual(eerste.detectedMediaType, .audio)

        let tweede = parser.parse(
            data: Data(
                """
                <rss version="2.0"><channel><title>Ander kanaal</title>
                  <item><title>Twee</title></item>
                </channel></rss>
                """.utf8))

        XCTAssertEqual(tweede.title, "Ander kanaal")
        XCTAssertEqual(tweede.items.map(\.title), ["Twee"])
        XCTAssertEqual(tweede.detectedMediaType, .unknown)
    }
}
