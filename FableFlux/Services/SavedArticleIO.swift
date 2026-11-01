import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Export/import van bewaarde artikelen inclusief tags (#220), voor backup/herstel
/// binnen FableFlux zelf (toestelwissel, noodgeval) — geen eis vanuit externe tools.
struct SavedArticleExportItem: Codable {
    var title: String
    var link: String?
    var itemDescription: String?
    var pubDate: Date?
    var guid: String?
    var tags: [String]
    var feedTitle: String?
    var feedURL: String?
}

enum SavedArticleIO {

    /// Alleen artikelen die nú bewaard zijn (`isSaved == true`) — geen historie van
    /// ooit-bewaard-en-weer-unsaved items (besluit Peter, #220).
    static func export(_ items: [FeedItem]) -> Data {
        let exportItems = items.map { item in
            SavedArticleExportItem(
                title: item.title,
                link: item.link,
                itemDescription: item.itemDescription,
                pubDate: item.pubDate,
                guid: item.guid,
                tags: item.effectiveTags,
                feedTitle: item.feed?.title,
                feedURL: item.feed?.url
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(exportItems)) ?? Data()
    }

    /// Importeert bewaarde artikelen. Dubbele herkenning op `guid` (of anders `link`) om
    /// hetzelfde artikel niet dubbel te importeren. Ontbreekt de bronfeed op dit toestel,
    /// dan wordt een placeholder-feed aangemaakt op basis van de opgeslagen titel/url
    /// (besluit Peter, #220). Geeft het aantal geïmporteerde artikelen.
    @discardableResult
    static func importArticles(from data: Data, context: ModelContext) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([SavedArticleExportItem].self, from: data) else { return 0 }

        var added = 0
        for export in items {
            guard !alreadyExists(export, context: context) else { continue }

            let item = FeedItem(
                title: export.title,
                link: export.link,
                itemDescription: export.itemDescription,
                pubDate: export.pubDate,
                guid: export.guid
            )
            item.isSaved = true
            item.isRead = true
            item.tags = export.tags
            item.feed = resolveFeed(title: export.feedTitle, url: export.feedURL, context: context)
            context.insert(item)
            added += 1
        }
        return added
    }

    private static func alreadyExists(_ export: SavedArticleExportItem, context: ModelContext) -> Bool {
        if let guid = export.guid, !guid.isEmpty {
            let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.guid == guid })
            if let count = try? context.fetchCount(descriptor), count > 0 { return true }
        }
        if let link = export.link, !link.isEmpty {
            let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.link == link })
            if let count = try? context.fetchCount(descriptor), count > 0 { return true }
        }
        return false
    }

    /// Vindt de bestaande feed op url, of maakt een placeholder-feed aan zodat een
    /// geïmporteerd artikel altijd leesbaar is, ook als de oorspronkelijke feed op dit
    /// toestel niet (meer) bestaat.
    private static func resolveFeed(title: String?, url: String?, context: ModelContext) -> Feed? {
        guard let url, !url.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == url })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let placeholder = Feed(url: url, title: (title?.isEmpty == false ? title! : url))
        context.insert(placeholder)
        return placeholder
    }
}

/// `Transferable`-wrapper voor `ShareLink`: zelfde patroon als `OPMLDocument` (#217).
struct SavedArticlesExportDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            document.data
        }
        .suggestedFileName("fableflux-bewaard.json")
    }
}
