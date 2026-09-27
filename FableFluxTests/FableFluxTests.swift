//
//  FableFluxTests.swift
//  FableFluxTests
//
//  Created by Peter Bijkerk on 29/07/2026.
//

import XCTest
@testable import FableFlux

/// Deterministische unit-tests voor de clustering-toewijzing. Ze toetsen de
/// geïsoleerde, pure logica (`wordBoundaryText` + `assignedTopic`) zonder netwerk,
/// Claude-call of live SwiftData-store. `TopicClusteringService` is `@MainActor`,
/// dus alle tests draaien op de MainActor.
@MainActor
final class FableFluxTests: XCTestCase {

    /// Bouwt de genormaliseerde topics net als `cluster(...)`: elke trefwoord-frase
    /// wordt via `wordBoundaryText` op woordgrens omsloten.
    private func normalized(
        _ service: TopicClusteringService,
        _ topics: [(name: String, keywords: [String])]
    ) -> [(name: String, phrases: [String])] {
        topics.map { topic in
            (topic.name, topic.keywords.map { service.wordBoundaryText($0) })
        }
    }

    // MARK: - 1. Woordgrens

    func testWordBoundaryMatchesWholeWordOnly() {
        let service = TopicClusteringService()

        // "ai" als deelstring in "email" mag niet als heel woord matchen.
        XCTAssertFalse(
            service.wordBoundaryText("email").contains(" ai "),
            "\"email\" mag geen hele-woord-treffer \" ai \" opleveren"
        )
        // "ai" als eigen woord moet wél matchen.
        XCTAssertTrue(
            service.wordBoundaryText("new ai model").contains(" ai "),
            "\"new ai model\" moet het hele woord \" ai \" bevatten"
        )
    }

    // MARK: - 2. Meerwoord-frase

    func testMultiWordPhraseMatchesOnlyWhenAdjacent() {
        let service = TopicClusteringService()
        let topics = normalized(service, [("AI", ["machine learning"])])

        // Aangrenzende frase matcht.
        let matchText = service.wordBoundaryText("machine learning breakthrough announced")
        XCTAssertEqual(
            service.assignedTopic(forText: matchText, normalizedTopics: topics, minimumScore: 1),
            "AI"
        )

        // Losse, niet-aangrenzende woorden matchen de frase niet.
        let noMatchText = service.wordBoundaryText("a learning method for a machine")
        XCTAssertNil(
            service.assignedTopic(forText: noMatchText, normalizedTopics: topics, minimumScore: 1)
        )
    }

    // MARK: - 3. Case-insensitiviteit

    func testMatchingIsCaseInsensitive() {
        let service = TopicClusteringService()
        let topics = normalized(service, [("AI", ["ai"])])

        let upper = service.wordBoundaryText("New AI Model Released")
        XCTAssertEqual(
            service.assignedTopic(forText: upper, normalizedTopics: topics, minimumScore: 1),
            "AI",
            "Hoofdletters moeten even goed matchen als kleine letters"
        )
    }

    // MARK: - 4. Minimumdrempel

    func testBelowMinimumScoreReturnsNil() {
        let service = TopicClusteringService()
        let topics = normalized(service, [("AI", ["ai", "machine learning"])])

        // Geen enkele trefwoord-treffer → score 0 < minimumdrempel → geen toewijzing.
        let text = service.wordBoundaryText("a quiet afternoon in the garden")
        XCTAssertNil(
            service.assignedTopic(
                forText: text,
                normalizedTopics: topics,
                minimumScore: AppConfiguration.minimumClusterScore
            )
        )

        // Eén echte treffer, maar de drempel opgeschroefd tot 2 → nog steeds nil.
        let oneHit = service.wordBoundaryText("new ai model")
        XCTAssertNil(
            service.assignedTopic(forText: oneHit, normalizedTopics: topics, minimumScore: 2),
            "Eén treffer onder een drempel van 2 mag geen onderwerp toewijzen"
        )
    }

    // MARK: - 5. Tie-break op genormaliseerde score

    func testTieBreakPrefersHigherNormalizedScore() {
        let service = TopicClusteringService()
        // Beide onderwerpen scoren 1 ruwe treffer op "alpha"; het onderwerp met de
        // kortere frasenlijst heeft de hogere genormaliseerde score en wint.
        let topics = normalized(
            service,
            [
                ("Breed", ["alpha", "beta", "gamma"]),  // normalized = 1/3
                ("Smal", ["alpha"]),  // normalized = 1/1
            ])
        let text = service.wordBoundaryText("an alpha release")

        XCTAssertEqual(
            service.assignedTopic(forText: text, normalizedTopics: topics, minimumScore: 1),
            "Smal",
            "Bij gelijke ruwe score wint het onderwerp met de hogere genormaliseerde score"
        )

        // Ongevoelig voor lijstvolgorde: omgekeerde volgorde geeft hetzelfde resultaat.
        let reversed = normalized(
            service,
            [
                ("Smal", ["alpha"]),
                ("Breed", ["alpha", "beta", "gamma"]),
            ])
        XCTAssertEqual(
            service.assignedTopic(forText: text, normalizedTopics: reversed, minimumScore: 1),
            "Smal"
        )
    }
}
