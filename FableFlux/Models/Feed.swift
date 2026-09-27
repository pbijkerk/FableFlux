import SwiftData
import Foundation

@Model
class Feed {
    var id: UUID
    var url: String
    var title: String
    var feedDescription: String?
    var lastRefreshed: Date?
    var faviconURL: String?
    var retentionDays: Int?  // nil = gebruik globale standaard; 0 = nooit verwijderen
    var biasScore: Int?  // -2 (links) … +2 (rechts), nil = onbekend
    var reliabilityLevel: String?  // "high", "mixed", "low"
    var ratingSource: String?  // bijv. "AllSides, MBFC"
    var biasRatedAt: Date?
    /// Telt deze feed mee in de AI-samenvatting op Vandaag? Staat los van zichtbaarheid:
    /// een uitgesloten feed blijft gewoon in Artikelen en Bewaard staan.
    var includedInSummary: Bool = true
    @Relationship var folder: FeedFolder?
    @Relationship(deleteRule: .cascade) var items: [FeedItem] = []

    /// True als dit een virtuele Mastodon-feed is (geen RSS).
    var isMastodonFeed: Bool { url.hasPrefix("mastodon://") }

    /// Favicon-URL via DuckDuckGo favicon-API — altijd beschikbaar, geen API-sleutel nodig.
    var faviconImageURL: URL? {
        guard let host = URL(string: url)?.host else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    init(url: String, title: String = "New Feed", feedDescription: String? = nil) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.feedDescription = feedDescription
    }
}
