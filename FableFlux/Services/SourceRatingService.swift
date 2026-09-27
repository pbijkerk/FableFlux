import Foundation
import OSLog

/// Immutable snapshot van een bronbeoordeling uit de gebundelde database.
struct SourceRating: Decodable, Sendable {
    let domain: String
    let name: String
    /// Politieke positie: -2 (ver links) … 0 (centrum) … +2 (ver rechts)
    let biasScore: Int
    /// Feitelijke betrouwbaarheid: "high", "mixed" of "low"
    let reliability: String
    /// Beoordelaars, bijv. ["AllSides", "MBFC"]
    let raters: [String]

    enum CodingKeys: String, CodingKey {
        case domain, name, reliability, raters
        case biasScore = "bias_score"
    }
}

/// Leest de gebundelde `source_ratings.json` en biedt domein-lookups.
/// Thread-safe: alle state is read-only na init.
final class SourceRatingService: Sendable {
    static let shared = SourceRatingService()

    private let ratings: [String: SourceRating]
    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: "ratings"
    )

    private init() {
        guard
            let url = Bundle.main.url(forResource: "source_ratings", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            logger.error("source_ratings.json niet gevonden in bundle")
            ratings = [:]
            return
        }

        struct Root: Decodable { let sources: [SourceRating] }
        do {
            let root = try JSONDecoder().decode(Root.self, from: data)
            ratings = Dictionary(root.sources.map { ($0.domain, $0) }, uniquingKeysWith: { first, _ in first })
            logger.info("Geladen: \(root.sources.count) bronbeoordelingen")
        } catch {
            logger.error("Decoderen source_ratings.json mislukt: \(error)")
            ratings = [:]
        }
    }

    /// Geeft de beoordeling voor de bron-URL van een feed terug, of nil als onbekend.
    func rating(forFeedURL feedURL: String) -> SourceRating? {
        guard let host = URL(string: feedURL)?.host?.lowercased() else { return nil }
        if let match = ratings[host] { return match }
        // Probeer zonder www.-prefix
        if host.hasPrefix("www.") {
            return ratings[String(host.dropFirst(4))]
        }
        return nil
    }

    /// Past de beoordeling toe op een Feed-object (aanroepen vanuit @MainActor context).
    @MainActor
    func applyRating(to feed: Feed) {
        guard let r = rating(forFeedURL: feed.url) else { return }
        feed.biasScore = r.biasScore
        feed.reliabilityLevel = r.reliability
        feed.ratingSource = r.raters.joined(separator: ", ")
        feed.biasRatedAt = Date()
    }
}
