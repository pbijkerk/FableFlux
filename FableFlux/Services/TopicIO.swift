import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Export/import van onderwerpen (#219): alleen configuratie (naam, keywords, favoriet),
/// geen samenvattingshistorie — die wordt toch opnieuw gegenereerd (besluit Peter).
struct TopicExportItem: Codable {
    var name: String
    var keywords: [String]
    var isLiked: Bool
    var isUserDefined: Bool
}

enum TopicIO {

    static func export(_ topics: [Topic]) -> Data {
        let items = topics.map {
            TopicExportItem(
                name: $0.name, keywords: $0.keywords, isLiked: $0.isLiked, isUserDefined: $0.isUserDefined)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(items)) ?? Data()
    }

    /// Voegt onderwerpen toe die nog niet bestaan (hoofdletterongevoelig op naam).
    /// Een bestaand onderwerp met dezelfde naam blijft ongewijzigd — geen samenvoegen,
    /// geen overschrijven (besluit Peter, #219). Geeft het aantal toegevoegde onderwerpen.
    @discardableResult
    static func importTopics(from data: Data, existing: [Topic], context: ModelContext) -> Int {
        guard let items = try? JSONDecoder().decode([TopicExportItem].self, from: data) else { return 0 }
        let existingNames = Set(existing.map { $0.name.lowercased() })

        var added = 0
        for item in items {
            guard !item.name.isEmpty, !existingNames.contains(item.name.lowercased()) else { continue }
            let topic = Topic(
                name: item.name, keywords: item.keywords, isLiked: item.isLiked, isUserDefined: item.isUserDefined)
            context.insert(topic)
            added += 1
        }
        return added
    }
}

/// `Transferable`-wrapper voor `ShareLink`: zelfde patroon als `OPMLDocument` (#217).
struct TopicExportDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            document.data
        }
        .suggestedFileName("fableflux-onderwerpen.json")
    }
}
