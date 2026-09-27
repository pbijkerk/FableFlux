import SwiftData
import Foundation

@Model
class FactCheckResult {
    var id: UUID
    var claim: String
    var verdict: String
    var rater: String
    var resultURL: String?
    var fetchedAt: Date
    var feedItem: FeedItem?

    init(claim: String, verdict: String, rater: String, resultURL: String? = nil) {
        self.id = UUID()
        self.claim = claim
        self.verdict = verdict
        self.rater = rater
        self.resultURL = resultURL
        self.fetchedAt = Date()
    }
}

// MARK: - Betwijfeld-classificatie (R7)

extension FactCheckResult {
    /// Deterministische (geen AI-call) classificatie of dit verdict een *betwijfelde*
    /// bewering aanduidt. Puur op basis van de vrije `verdict`-tekst.
    var isDisputed: Bool { Self.isDisputedVerdict(verdict) }

    /// Verdict-termen die wijzen op een betwijfelde bewering (EN + NL).
    private static let disputedTerms = [
        "false", "misleading", "incorrect", "unsupported", "inaccurate",
        "pants on fire", "onwaar", "onjuist", "misleidend", "nep",
    ]

    /// Vertrouwde termen die een betwijfeld-classificatie expliciet uitsluiten
    /// (ook varianten als "mostly true"); nemen voorrang op de betwijfeld-termen.
    private static let trustedTerms = ["true", "correct", "accurate"]

    /// Bepaalt op woordgrenzen of een verdict betwijfeld is. Woordgrenzen voorkomen
    /// dat "accurate" binnen "inaccurate" of "correct" binnen "incorrect" als
    /// vertrouwd geldt; een vertrouwde term wint van een betwijfelde term.
    static func isDisputedVerdict(_ verdict: String) -> Bool {
        let lower = verdict.lowercased()
        if trustedTerms.contains(where: { lower.containsWord($0) }) { return false }
        return disputedTerms.contains(where: { lower.containsWord($0) })
    }
}

extension String {
    /// True als `word` als heel woord/hele frase in de string voorkomt (woordgrenzen).
    fileprivate func containsWord(_ word: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return range(of: pattern, options: [.regularExpression]) != nil
    }
}
