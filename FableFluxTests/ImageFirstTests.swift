//
//  ImageFirstTests.swift
//  FableFluxTests
//

import UIKit
import XCTest

@testable import FableFlux

/// Beeldbron, afmetingsfilter, wifi-instelling en leesmarkering (#225).
@MainActor
final class ImageFirstTests: XCTestCase {

    private let base = URL(string: "https://www.example.com/nieuws/artikel-1")!

    // MARK: - og:image

    func testOgImageUitDeHead() {
        let html = """
            <html><head><meta charset="utf-8">
            <meta property="og:title" content="Titel">
            <meta property="og:image" content="https://cdn.example.com/foto.jpg">
            </head><body></body></html>
            """
        XCTAssertEqual(
            ArticleImageService.pageImageURL(fromHTML: html, baseURL: base), "https://cdn.example.com/foto.jpg")
    }

    func testAttributenInAndereVolgordeEnEnkeleQuotes() {
        let html = "<meta content='https://cdn.example.com/a.png' property='og:image' />"
        XCTAssertEqual(
            ArticleImageService.pageImageURL(fromHTML: html, baseURL: base), "https://cdn.example.com/a.png")
    }

    func testSecureUrlGaatVoorEnEntiteitenWordenOpgelost() {
        let html = """
            <meta property="og:image" content="http://cdn.example.com/b.jpg">
            <meta property="og:image:secure_url" content="https://cdn.example.com/b.jpg?w=1200&amp;h=630">
            """
        XCTAssertEqual(
            ArticleImageService.pageImageURL(fromHTML: html, baseURL: base),
            "https://cdn.example.com/b.jpg?w=1200&h=630")
    }

    func testRelatieveUrlWordtOpgelost() {
        let html = #"<meta property="og:image" content="/media/c.jpg">"#
        XCTAssertEqual(
            ArticleImageService.pageImageURL(fromHTML: html, baseURL: base), "https://www.example.com/media/c.jpg")
    }

    func testTwitterImageAlsTerugval() {
        let html = #"<meta name="twitter:image" content="https://cdn.example.com/t.jpg">"#
        XCTAssertEqual(
            ArticleImageService.pageImageURL(fromHTML: html, baseURL: base), "https://cdn.example.com/t.jpg")
    }

    func testLogoIconenEnTrackersVallenAf() {
        for content in [
            "https://www.example.com/favicon.ico", "https://www.example.com/static/logo.png",
            "https://t.example.com/pixel.gif", "https://www.example.com/icon.svg",
            "https://cdn.example.net/uploads/cropped-site-logo-512_480.png",
            "https://assets.example.nl/img/social/default-og-image-facebook.png",
        ] {
            let html = #"<meta property="og:image" content="\#(content)">"#
            XCTAssertNil(ArticleImageService.pageImageURL(fromHTML: html, baseURL: base), content)
        }
    }

    func testGeenAfbeelding() {
        XCTAssertNil(ArticleImageService.pageImageURL(fromHTML: "<html><head></head></html>", baseURL: base))
    }

    // MARK: - Afmeting

    func testTeKleineAfbeeldingWordtGeweigerd() throws {
        XCTAssertNil(ArticleImageService.downsample(try png(width: 120, height: 120), maxPixelSize: 1200))
        XCTAssertNil(
            ArticleImageService.downsample(try png(width: 800, height: 150), maxPixelSize: 1200),
            "Een smalle banner is geen artikelbeeld")
    }

    func testGroteAfbeeldingWordtVerkleind() throws {
        let image = try XCTUnwrap(
            ArticleImageService.downsample(try png(width: 2400, height: 1600), maxPixelSize: 1200))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(max(cg.width, cg.height), 1200)
    }

    func testGeenAfbeeldingsdata() {
        XCTAssertNil(ArticleImageService.downsample(Data("<html>".utf8), maxPixelSize: 1200))
    }

    private func png(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    // MARK: - Alleen via wifi

    func testAlleenViaWifiLaadtNietOpMobielNetwerk() {
        XCTAssertTrue(ImageLoadPolicy.allowsNetwork(policy: .always, onExpensiveNetwork: true))
        XCTAssertTrue(ImageLoadPolicy.allowsNetwork(policy: .wifiOnly, onExpensiveNetwork: false))
        XCTAssertFalse(ImageLoadPolicy.allowsNetwork(policy: .wifiOnly, onExpensiveNetwork: true))
    }

    // MARK: - Leestijd

    func testLeestijdAlleenBijGenoegTekst() {
        XCTAssertNil(ImageFirstCard.readingMinutes(for: "Korte samenvatting van een paar woorden."))
        let lang = Array(repeating: "woord", count: 600).joined(separator: " ")
        XCTAssertEqual(ImageFirstCard.readingMinutes(for: lang), 3)
    }

    // MARK: - Leesmarkering

    private func verseDefaults() -> UserDefaults {
        let naam = "ImageFirstTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: naam)!
        defaults.removePersistentDomain(forName: naam)
        return defaults
    }

    func testMarkeringSchuiftPasOpBijNaarDeAchtergrond() {
        let defaults = verseDefaults()
        let store = ReadingMarkerStore(defaults: defaults)
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)

        store.noteSeen(t1, in: "all")
        XCTAssertNil(store.marker(for: "all"), "Nog niet vastgelegd tijdens de sessie")
        store.commitAll()
        XCTAssertEqual(store.marker(for: "all"), t1)

        store.noteSeen(t2, in: "all")
        store.noteSeen(t1, in: "all")
        XCTAssertEqual(store.marker(for: "all"), t1, "De lijn verspringt niet terwijl je leest")
        store.commitAll()
        XCTAssertEqual(store.marker(for: "all"), t2, "Alleen een nieuwer artikel schuift op")
    }

    func testMarkeringBlijftNaHerstart() {
        let defaults = verseDefaults()
        let t = Date(timeIntervalSince1970: 5_000)
        ReadingMarkerStore(defaults: defaults).noteSeen(t, in: "folder:x")
        ReadingMarkerStore(defaults: defaults).commitAll()
        // Een nieuwe store op dezelfde opslag = de app na een herstart.
        XCTAssertEqual(ReadingMarkerStore(defaults: defaults).marker(for: "folder:x"), t)
        XCTAssertNil(ReadingMarkerStore(defaults: defaults).marker(for: "all"), "Per lijst apart")
    }

    func testPlaatsVanDeLijn() {
        let marker = Date(timeIntervalSince1970: 100)
        let dates: [Date?] = [200, 150, 100, 50].map { Date(timeIntervalSince1970: $0) }
        XCTAssertEqual(ReadingMarker.dividerIndex(dates: dates, marker: marker), 2)
        XCTAssertNil(ReadingMarker.dividerIndex(dates: dates, marker: nil), "Nooit eerder gezien")
        XCTAssertNil(
            ReadingMarker.dividerIndex(dates: dates, marker: Date(timeIntervalSince1970: 300)),
            "Niets nieuws: geen lijn bovenaan")
        XCTAssertNil(
            ReadingMarker.dividerIndex(dates: dates, marker: Date(timeIntervalSince1970: 10)),
            "Alles nieuw: geen lijn")
        XCTAssertEqual(
            ReadingMarker.dividerIndex(dates: [Date(timeIntervalSince1970: 200), nil], marker: marker), 1,
            "Een artikel zonder datum telt als oud")
    }
}
