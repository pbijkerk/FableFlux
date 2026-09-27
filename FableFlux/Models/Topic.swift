import SwiftData
import Foundation

@Model
class Topic {
    var id: UUID
    var name: String
    var keywords: [String]
    var isLiked: Bool
    var isUserDefined: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var summaries: [TopicSummary] = []

    init(name: String, keywords: [String] = [], isLiked: Bool = false, isUserDefined: Bool = false) {
        self.id = UUID()
        self.name = name
        self.keywords = keywords
        self.isLiked = isLiked
        self.isUserDefined = isUserDefined
        self.createdAt = Date()
    }
}

// MARK: - SummaryItem

/// Type-safe koppeling van titel + link; vervangt de losse parallelle arrays.
struct SummaryItem: Codable, Sendable {
    let title: String
    let link: String
}

@Model
class TopicSummary {
    var id: UUID
    var topicName: String
    var summaryText: String
    var createdAt: Date
    // Onderliggende opslag — privé zodat callers altijd via `items` gaan
    private var itemTitles: [String]
    private var itemLinks: [String]
    var topic: Topic?

    /// Atomische getter/setter: voorkomt desync van de twee onderliggende arrays.
    var items: [SummaryItem] {
        get { zip(itemTitles, itemLinks).map { SummaryItem(title: $0, link: $1) } }
        set {
            itemTitles = newValue.map { $0.title }
            itemLinks = newValue.map { $0.link }
        }
    }

    init(topicName: String, summaryText: String, items: [SummaryItem]) {
        self.id = UUID()
        self.topicName = topicName
        self.summaryText = summaryText
        self.createdAt = Date()
        self.itemTitles = items.map { $0.title }
        self.itemLinks = items.map { $0.link }
    }
}
