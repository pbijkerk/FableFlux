import Foundation
import SwiftData

/// De drie bedoelingen die een artikel kan hebben (#224): gewoon feedartikel, korte
/// leesstapel met termijn, of bewust archief zonder termijn.
enum LaterStatus: String, Codable {
    case regular = "none"
    case readLater
    case saved
}

extension FeedItem {
    /// Afgeleid uit de opgeslagen velden. Bewaard wint van Lees later: bewaren haalt een
    /// artikel altijd uit de leesstapel (`ReadLater.save`), maar ook bij een inconsistente
    /// rij is het veilige antwoord "bewaard" — dat wordt nooit opgeruimd.
    var laterStatus: LaterStatus {
        if isSaved { return .saved }
        if readLaterAddedAt != nil { return .readLater }
        return .regular
    }

    /// De bronnaam: de feed, of — als die is verwijderd — de naam van het moment van bewaren.
    var sourceTitle: String? { feed?.title ?? savedSourceTitle }

    /// Sorteersleutel voor Bewaard: moment van bewaren, met de artikeldatum als terugval
    /// voor artikelen die vóór #224 zijn bewaard.
    var savedSortDate: Date { savedAt ?? effectiveDate ?? .distantPast }
}

/// Regels voor Lees later en Bewaard (#224). Puur op het model, zonder UI, zodat de
/// termijn- en opruimregels los te testen zijn met een geïnjecteerde datum.
enum ReadLater {

    /// Vanaf hoeveel dagen vóór het verlopen de chip "verloopt over X dagen" verschijnt.
    static let warningDays = 2

    /// Keuzes voor de termijn in Instellingen; 0 = nooit verlopen.
    static let termOptions: [(label: String, days: Int)] = [
        ("7 dagen", 7),
        ("14 dagen", 14),
        ("30 dagen", 30),
        ("Nooit", 0),
    ]

    /// De ingestelde termijn in dagen (0 = nooit). Eén algemene instelling, niet per feed
    /// (besluit Peter, #224).
    static var termDays: Int {
        UserDefaults.standard.object(forKey: AppConfiguration.UserDefaultsKeys.readLaterDays) as? Int
            ?? AppConfiguration.defaultReadLaterDays
    }

    // MARK: - Termijn

    /// Wanneer het artikel uit Lees later verdwijnt, of `nil` als het er niet in staat of
    /// de termijn "nooit" is.
    static func expiresAt(_ item: FeedItem, termDays: Int) -> Date? {
        guard termDays > 0, !item.isSaved, let added = item.readLaterAddedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: termDays, to: added)
    }

    /// Hele dagen tot het verlopen, naar boven afgerond: een artikel dat over 30 uur
    /// verloopt, heeft "nog 2 d". 0 = verloopt vandaag (of is al verlopen).
    static func daysLeft(_ item: FeedItem, termDays: Int, now: Date = Date()) -> Int? {
        guard let expires = expiresAt(item, termDays: termDays) else { return nil }
        let seconds = expires.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 86_400).rounded(.up))
    }

    static func isExpired(_ item: FeedItem, termDays: Int, now: Date = Date()) -> Bool {
        guard let expires = expiresAt(item, termDays: termDays) else { return false }
        return expires <= now
    }

    /// Of de waarschuwing "verloopt over X dagen" (met Verlengen/Bewaren) hoort te staan.
    static func isInWarningWindow(_ item: FeedItem, termDays: Int, now: Date = Date()) -> Bool {
        guard let left = daysLeft(item, termDays: termDays, now: now) else { return false }
        return left <= warningDays && !isExpired(item, termDays: termDays, now: now)
    }

    // MARK: - Acties

    static func addToReadLater(_ item: FeedItem, now: Date = Date()) {
        guard !item.isSaved else { return }
        item.readLaterAddedAt = now
    }

    static func removeFromReadLater(_ item: FeedItem) {
        item.readLaterAddedAt = nil
    }

    /// Verlengen: de termijn begint opnieuw.
    static func extend(_ item: FeedItem, now: Date = Date()) {
        guard item.readLaterAddedAt != nil else { return }
        item.readLaterAddedAt = now
    }

    /// Bewaren: haalt het artikel uit Lees later en legt een lokale kopie van de tekst en
    /// de bronnaam vast. `contentHTML` is de best beschikbare tekst (een al geëxtraheerd
    /// web-artikel); zonder die tekst valt dit terug op de feedtekst. Een al bewaarde
    /// lokale kopie wordt alleen vervangen door een aangeleverde, betere tekst.
    static func save(_ item: FeedItem, contentHTML: String? = nil, now: Date = Date()) {
        if !item.isSaved { item.savedAt = now }
        item.isSaved = true
        item.readLaterAddedAt = nil
        item.savedSourceTitle = item.feed?.title ?? item.savedSourceTitle
        if let contentHTML, !contentHTML.isEmpty {
            item.savedContentHTML = contentHTML
        } else if item.savedContentHTML == nil, !item.sanitisedHTML.isEmpty {
            item.savedContentHTML = item.sanitisedHTML
        }
    }

    /// Uit Bewaard halen. De lokale kopie gaat weg (ruimte). Hangt het artikel niet meer aan
    /// een feed — die is verwijderd terwijl het bewaard was — dan wordt het verwijderd: anders
    /// blijft het als wees in de store staan, buiten bereik van elke opruimronde.
    ///
    /// `deleteOrphan: false` voor het leesscherm: daar is het artikel nog open en mag het
    /// niet onder de view vandaan verdwijnen. `removeOrphans` ruimt het later alsnog op.
    static func unsave(_ item: FeedItem, context: ModelContext, deleteOrphan: Bool = true) {
        item.isSaved = false
        item.savedAt = nil
        item.savedContentHTML = nil
        item.savedImageData = nil
        if deleteOrphan, item.feed == nil { context.delete(item) }
    }

    /// Verwijdert artikelen zonder feed die niet (meer) bewaard zijn: overblijfsels van een
    /// verwijderde feed die in het leesscherm uit Bewaard zijn gehaald.
    static func removeOrphans(context: ModelContext) {
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { $0.feed == nil && !$0.isSaved }
        )
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        for item in orphans { context.delete(item) }
        context.saveOrLog("losse, niet-bewaarde artikelen op te ruimen")
    }

    // MARK: - Opruimen

    /// Haalt verlopen artikelen van één feed uit Lees later. Ze worden niet verwijderd:
    /// ze vallen terug onder de opruimtermijn van hun feed (besluit Peter, #224). Telt die
    /// termijn vanaf de publicatiedatum, dan kan een oud artikel bij dezelfde opruimronde
    /// alsnog verdwijnen; dat is bewust zo.
    static func expireItems(feedID: UUID, context: ModelContext, termDays: Int, now: Date = Date()) {
        guard termDays > 0,
            let cutoff = Calendar.current.date(byAdding: .day, value: -termDays, to: now)
        else { return }
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { item in
                item.feed?.id == feedID && !item.isSaved && item.readLaterAddedAt != nil
            }
        )
        guard let candidates = try? context.fetch(descriptor) else { return }
        for item in candidates {
            if let added = item.readLaterAddedAt, added <= cutoff {
                item.readLaterAddedAt = nil
            }
        }
    }

    /// Vóór het verwijderen van een feed: bewaarde artikelen loskoppelen, zodat ze niet via
    /// de cascade meegaan en offline leesbaar blijven (#224). Lees later-artikelen gaan wel
    /// mee: dat is een tijdelijke stapel, geen archief.
    static func detachSavedItems(from feed: Feed) {
        let saved = feed.items.filter(\.isSaved)
        guard !saved.isEmpty else { return }
        feed.items.removeAll { $0.isSaved }
        for item in saved {
            item.savedSourceTitle = item.savedSourceTitle ?? feed.title
            item.feed = nil
        }
    }

    // MARK: - Offline afbeelding

    /// Grootste afbeelding die lokaal wordt bewaard; daarboven blijft het bij de URL.
    static let maxImageBytes = 5 * 1024 * 1024

    /// Haalt de artikelafbeelding op en bewaart die bij het artikel, zodat het offline
    /// leesbaar blijft. Stil bij fouten: zonder afbeelding blijft de tekst gewoon leesbaar.
    @MainActor
    static func storeImage(for item: FeedItem, context: ModelContext) async {
        guard item.isSaved, item.savedImageData == nil,
            let urlString = item.imageURL, let url = URL(string: urlString),
            url.scheme?.hasPrefix("http") == true
        else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
            !data.isEmpty, data.count <= maxImageBytes,
            item.isSaved  // intussen niet weer uit Bewaard gehaald
        else { return }
        item.savedImageData = data
        context.saveOrLog("de afbeelding van het bewaarde artikel op te slaan")
    }
}
