import Foundation
import SwiftData

/// Schrijft een verversing weg in een eigen achtergrondcontext op dezelfde container, zodat
/// het SwiftData-werk (bestaande artikelen ophalen, invoegen, opruimen, opslaan) niet op de
/// main thread met het scrollen concurreert (#153). De hoofdcontext neemt de opgeslagen
/// wijzigingen daarna over; `@Query`-schermen werken zo vanzelf bij.
///
/// Maak hem buiten de main thread aan (zie `FeedRefreshService.writer(for:)`): anders hangt
/// zijn context aan de main queue en draait het werk toch daar.
@ModelActor
actor FeedWriter {
    /// Verwerkt een geparste feed voor de feed met dit id en slaat op. Doet niets als de feed
    /// intussen is verwijderd.
    func apply(_ parsed: ParsedFeed, toFeedWith id: PersistentIdentifier) throws {
        guard let feed = self[id, as: Feed.self] else { return }
        FeedRefreshService.applyParsedFeed(parsed, to: feed, context: modelContext)
        try modelContext.save()
    }
}
