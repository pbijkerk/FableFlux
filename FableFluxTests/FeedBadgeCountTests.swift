//
//  FeedBadgeCountTests.swift
//  FableFluxTests
//

import SwiftData
import XCTest

@testable import FableFlux

/// Toetst dat de teller per feed via `fetchCount` dezelfde aantallen geeft als de oude
/// telling over `feed.items`, in beide tellerstanden (#121).
@MainActor
final class FeedBadgeCountTests: XCTestCase {

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

    private func maakFeeds() throws -> [Feed] {
        let context = container.mainContext
        let verdeling: [(totaal: Int, gelezen: Int)] = [(5, 2), (3, 3), (0, 0), (4, 0)]
        var feeds: [Feed] = []
        for (index, aantallen) in verdeling.enumerated() {
            let feed = Feed(url: "https://f\(index).example.com/rss", title: "Feed \(index)")
            context.insert(feed)
            for i in 0..<aantallen.totaal {
                let item = FeedItem(title: "A\(index)-\(i)")
                item.isRead = i < aantallen.gelezen
                item.feed = feed
                context.insert(item)
            }
            feeds.append(feed)
        }
        try context.save()
        return feeds
    }

    func testTotaalGelijkAanOudeTelling() throws {
        let feeds = try maakFeeds()
        let tellers = FeedBadgeCounter.counts(for: feeds, unreadOnly: false, context: container.mainContext)

        for feed in feeds {
            XCTAssertEqual(tellers[feed.id], feed.items.count, feed.title)
        }
        XCTAssertEqual(feeds.map { tellers[$0.id] }, [5, 3, 0, 4])
    }

    func testOngelezenGelijkAanOudeTelling() throws {
        let feeds = try maakFeeds()
        let tellers = FeedBadgeCounter.counts(for: feeds, unreadOnly: true, context: container.mainContext)

        for feed in feeds {
            XCTAssertEqual(tellers[feed.id], feed.items.filter { !$0.isRead }.count, feed.title)
        }
        XCTAssertEqual(feeds.map { tellers[$0.id] }, [3, 0, 0, 4])
    }

    func testTellerVolgtEenGelezenArtikel() throws {
        let feeds = try maakFeeds()
        let context = container.mainContext
        let artikel = try XCTUnwrap(feeds[3].items.first)
        artikel.isRead = true
        try context.save()

        let tellers = FeedBadgeCounter.counts(for: feeds, unreadOnly: true, context: context)
        XCTAssertEqual(tellers[feeds[3].id], 3)
    }
}
