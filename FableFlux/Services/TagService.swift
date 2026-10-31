import SwiftData
import Foundation

/// Beheert tags op bewaarde items (#215): hoofdletterongevoelige normalisatie
/// ("Nieuws" en "nieuws" zijn dezelfde tag, de eerst-gebruikte schrijfwijze wint) en
/// autocomplete op eerder gebruikte tags over alle artikelen.
///
/// Tags blijven op een item staan ook nadat het 'unsaved' wordt (zie `FeedItem.tags`);
/// daarom verzamelt dit de bekende tags over *alle* `FeedItem`s, niet alleen de
/// bewaarde, zodat een hergebruikte tag altijd dezelfde schrijfwijze krijgt.
enum TagService {

    /// Alle bekende tags, hoofdletterongevoelig gededupliceerd (eerst-gebruikte
    /// schrijfwijze wint), alfabetisch gesorteerd op weergavevorm.
    static func allKnownTags(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<FeedItem>()
        guard let items = try? context.fetch(descriptor) else { return [] }

        var seenLowercased = Set<String>()
        var result: [String] = []
        for item in items {
            for tag in item.effectiveTags {
                let key = tag.lowercased()
                guard !seenLowercased.contains(key) else { continue }
                seenLowercased.insert(key)
                result.append(tag)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Suggesties voor autocomplete: bekende tags die de zoektekst bevatten en nog niet
    /// op `item` staan. Leeg bij een lege zoektekst (geen ongevraagde suggestielijst).
    static func suggestions(for query: String, excluding item: FeedItem, context: ModelContext) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let existing = item.effectiveTags
        return allKnownTags(context: context).filter { known in
            known.localizedCaseInsensitiveContains(trimmed)
                && !existing.contains { $0.caseInsensitiveCompare(known) == .orderedSame }
        }
    }

    /// Voegt `raw` toe als tag op `item`. Hergebruikt de schrijfwijze van een al bekende
    /// tag bij een hoofdletterongevoelige match (eerst-gebruikte casing wint); negeert
    /// lege invoer en een tag die al op dit item staat (ongeacht hoofdlettergebruik).
    @discardableResult
    static func addTag(_ raw: String, to item: FeedItem, context: ModelContext) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var tags = item.effectiveTags
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return false }

        let canonical =
            allKnownTags(context: context)
            .first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
        tags.append(canonical)
        item.tags = tags
        return true
    }

    /// Verwijdert `tag` (hoofdletterongevoelig) van `item`.
    static func removeTag(_ tag: String, from item: FeedItem) {
        item.tags = item.effectiveTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }
}
