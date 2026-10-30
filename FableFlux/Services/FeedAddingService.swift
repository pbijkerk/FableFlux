import Foundation
import SwiftData

/// Fout bij het toevoegen van een feed via `FeedAddingService.addFeed`. `errorDescription`
/// is bedoeld om direct aan de gebruiker te tonen (AddFeedView, ShareExtensionView).
enum FeedAddError: LocalizedError {
    case invalidURL
    case duplicate
    case notAFeed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ongeldig adres. Controleer het en probeer het opnieuw."
        case .duplicate:
            return "Deze feed staat al in je lijst."
        case .notAFeed(let underlying):
            return "Dit lijkt geen RSS/Atom-feed te zijn: \(underlying.localizedDescription)"
        }
    }
}

/// Herbruikbare kernlogica om een RSS/Atom-feed op een URL te valideren en toe te voegen
/// aan SwiftData (#201). Zowel `AddFeedView` (handmatige invoer) als
/// `FableFluxShareExtension` (Share Sheet vanuit de browser) roepen `addFeed` aan, en een
/// toekomstig `rssreader://`-URL-schema (#203) kan dezelfde functie hergebruiken.
///
/// Doet zelf geen volledige `FeedRefreshService.refresh` (dat zou de Mastodon-afhankelijkheden
/// van die service in de Share Extension-target trekken); in plaats daarvan slaat het de
/// geparste items van de eerste ophaalbeurt direct op, zodat de feed nooit leeg verschijnt.
/// De volgende reguliere verversing in de hoofdapp vult bronbeoordeling en mapindeling aan.
@MainActor
enum FeedAddingService {

    /// Normaliseert ruwe gebruikersinvoer naar een `http(s)`-URL-string: trimt whitespace en
    /// voegt `https://` toe als er geen schema is opgegeven (zoals de gebruiker "example.com/feed"
    /// kan intikken in AddFeedView).
    static func normalizedURLString(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }

    /// Valideert `rawURL`, haalt de feed op en slaat de feed + eerste artikelen op in `context`.
    ///
    /// - Throws: `FeedAddError.invalidURL` bij een onbruikbaar adres, `.duplicate` als de feed
    ///   al in de lijst staat, of `.notAFeed` als de URL geen RSS/Atom kon worden geparst.
    /// - Returns: de opgeslagen `Feed`.
    @discardableResult
    static func addFeed(from rawURL: String, context: ModelContext) async throws -> Feed {
        let urlString = normalizedURLString(from: rawURL)
        guard let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw FeedAddError.invalidURL
        }

        let existingDescriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == urlString })
        if let existingCount = try? context.fetchCount(existingDescriptor), existingCount > 0 {
            throw FeedAddError.duplicate
        }

        let parsed: ParsedFeed
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            parsed = try await Task.detached(priority: .utility) {
                RSSParser().parse(data: data)
            }.value
        } catch {
            throw FeedAddError.notAFeed(underlying: error)
        }

        // Een geldige feed heeft op z'n minst een titel óf items; anders was dit vermoedelijk
        // een gewone webpagina en geen RSS/Atom-document.
        guard !parsed.title.isEmpty || !parsed.items.isEmpty else {
            throw FeedAddError.notAFeed(underlying: URLError(.cannotParseResponse))
        }

        let feed = Feed(
            url: urlString,
            title: parsed.title.isEmpty ? urlString : parsed.title,
            feedDescription: parsed.description.isEmpty ? nil : parsed.description
        )
        context.insert(feed)

        let items = parsed.items.map { parsedItem in
            FeedItem(
                title: parsedItem.title,
                link: parsedItem.link.isEmpty ? nil : parsedItem.link,
                itemDescription: parsedItem.description.isEmpty ? nil : parsedItem.description,
                pubDate: parsedItem.pubDate,
                guid: parsedItem.guid.isEmpty ? nil : parsedItem.guid,
                enclosureURL: parsedItem.enclosureURL,
                enclosureMIMEType: parsedItem.enclosureMIMEType,
                imageURL: parsedItem.imageURL
            )
        }
        for item in items {
            item.feed = feed
            context.insert(item)
        }
        feed.items.append(contentsOf: items)
        feed.lastRefreshed = Date()

        try context.save()
        return feed
    }
}
