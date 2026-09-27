//
//  OPMLParserTests.swift
//  FableFluxTests
//

import XCTest

@testable import FableFlux

/// Toetst de mapindeling van `OPMLParser`. De teller die mappen bijhoudt mag niet
/// door de sluitingstag van een feed worden verlaagd; anders belandt elke feed ná
/// de eerste in "Overig" (zie #66/#78).
final class OPMLParserTests: XCTestCase {

    private func parse(_ xml: String) -> [OPMLFeed] {
        OPMLParser().parse(data: Data(xml.utf8))
    }

    func testMapMetMeerdereFeedsBehoudtDeMapnaam() {
        let feeds = parse(
            """
            <opml version="1.0"><body>
              <outline text="Tech">
                <outline xmlUrl="https://feed1.example/rss" text="Feed 1"/>
                <outline xmlUrl="https://feed2.example/rss" text="Feed 2"/>
                <outline xmlUrl="https://feed3.example/rss" text="Feed 3"/>
              </outline>
            </body></opml>
            """)

        XCTAssertEqual(feeds.count, 3)
        XCTAssertEqual(
            feeds.map(\.folderName), ["Tech", "Tech", "Tech"],
            "Ook de tweede en derde feed in een map horen bij die map"
        )
    }

    func testFeedBuitenEenMapHeeftGeenMapnaam() {
        let feeds = parse(
            """
            <opml version="1.0"><body>
              <outline xmlUrl="https://los.example/rss" text="Los"/>
              <outline text="Tech">
                <outline xmlUrl="https://feed1.example/rss" text="Feed 1"/>
              </outline>
              <outline xmlUrl="https://ook-los.example/rss" text="Ook los"/>
            </body></opml>
            """)

        XCTAssertEqual(feeds.map(\.folderName), [nil, "Tech", nil])
    }

    func testGenesteMapHoudtDeBuitensteMapnaamAan() {
        let feeds = parse(
            """
            <opml version="1.0"><body>
              <outline text="Buiten">
                <outline xmlUrl="https://feed1.example/rss" text="Feed 1"/>
                <outline text="Binnen">
                  <outline xmlUrl="https://feed2.example/rss" text="Feed 2"/>
                </outline>
                <outline xmlUrl="https://feed3.example/rss" text="Feed 3"/>
              </outline>
              <outline xmlUrl="https://feed4.example/rss" text="Feed 4"/>
            </body></opml>
            """)

        XCTAssertEqual(
            feeds.map(\.folderName), ["Buiten", "Buiten", "Buiten", nil],
            "De buitenste mapnaam wint, en na het sluiten van de map is er geen map meer"
        )
    }

    func testLegeMapVerstoortDeVolgendeFeedsNiet() {
        let feeds = parse(
            """
            <opml version="1.0"><body>
              <outline text="Leeg"/>
              <outline text="Tech">
                <outline xmlUrl="https://feed1.example/rss" text="Feed 1"/>
                <outline xmlUrl="https://feed2.example/rss" text="Feed 2"/>
              </outline>
            </body></opml>
            """)

        XCTAssertEqual(feeds.map(\.folderName), ["Tech", "Tech"])
    }
}
