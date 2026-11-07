import CoreTransferable
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
    /// Lees later of Bewaard (#224). Ontbreekt in bestanden van vóór #224; die artikelen
    /// waren toen per definitie bewaard en komen dus onder Bewaard binnen.
    var status: LaterStatus?
    var readLaterAddedAt: Date?
    var savedAt: Date?
    /// De lokale kopie van de tekst, zodat een hersteld bewaard artikel offline leesbaar is.
    var savedContentHTML: String?
}

enum SavedArticleIO {

    /// Alleen artikelen die nú in Lees later of Bewaard staan — geen historie van
    /// ooit-bewaard-en-weer-unsaved items (besluit Peter, #220). Andere artikelen in
    /// `items` worden overgeslagen.
    static func export(_ items: [FeedItem]) -> Data {
        let exportItems = items.filter { $0.laterStatus != .regular }.map { item in
            SavedArticleExportItem(
                title: item.title,
                link: item.link,
                itemDescription: item.itemDescription,
                pubDate: item.pubDate,
                guid: item.guid,
                tags: item.effectiveTags,
                feedTitle: item.sourceTitle,
                feedURL: item.feed?.url,
                status: item.laterStatus,
                readLaterAddedAt: item.readLaterAddedAt,
                savedAt: item.savedAt,
                savedContentHTML: item.savedContentHTML
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(exportItems)) ?? Data()
    }

    /// Importeert Lees later- en bewaarde artikelen. Dubbele herkenning op `guid` (of anders `link`) om
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
            item.tags = export.tags
            item.feed = resolveFeed(title: export.feedTitle, url: export.feedURL, context: context)
            context.insert(item)
            switch export.status ?? .saved {
            case .readLater:
                // Lees later is ongelezen werk; de termijn loopt door vanaf het oorspronkelijke
                // moment van toevoegen (verlopen items gaan bij de volgende opruimronde terug).
                ReadLater.addToReadLater(item, now: export.readLaterAddedAt ?? Date())
            case .saved, .regular:
                item.isRead = true
                item.savedSourceTitle = export.feedTitle
                ReadLater.save(item, contentHTML: export.savedContentHTML, now: export.savedAt ?? Date())
            }
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
