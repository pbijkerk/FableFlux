//
//  FableFluxTests.swift
//  FableFluxTests
//
//  Created by Peter Bijkerk on 29/07/2026.
//

import SwiftData
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

/// Opnieuw koppelen van een al bekend Mastodon-account werkt dat account bij in plaats van
/// een tweede account met een tweede feed aan te maken (#159). Keychain blijft buiten
/// beschouwing: de token-opslag wordt als closure ingevoerd en hier alleen vastgelegd.
@MainActor
final class MastodonAccountLinkerTests: XCTestCase {

    private var container: ModelContainer!
    private var savedTokens: [(token: String, instanceURL: String, accountID: String)] = []

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Feed.self, FeedItem.self, FeedFolder.self, Topic.self,
            TopicSummary.self, FactCheckResult.self, MastodonAccount.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        savedTokens = []
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func credentials(
        id: String = "42", username: String = "alice", displayName: String = "Alice"
    ) -> MastodonVerifyCredentials {
        MastodonVerifyCredentials(
            id: id, username: username, displayName: displayName, avatar: "https://example.social/a.png")
    }

    @discardableResult
    private func link(
        instanceURL: String = "https://example.social",
        credentials: MastodonVerifyCredentials,
        clientID: String = "client-1",
        token: String = "token-1"
    ) throws -> MastodonAccount {
        try MastodonAccountLinker.link(
            instanceURL: instanceURL, credentials: credentials, clientID: clientID,
            accessToken: token, context: container.mainContext
        ) { savedToken, savedInstanceURL, savedAccountID in
            savedTokens.append((savedToken, savedInstanceURL, savedAccountID))
        }
    }

    private func allAccounts() throws -> [MastodonAccount] {
        try container.mainContext.fetch(FetchDescriptor<MastodonAccount>())
    }

    private func mastodonFeeds() throws -> [Feed] {
        try container.mainContext.fetch(FetchDescriptor<Feed>()).filter(\.isMastodonFeed)
    }

    func testRelinkingSameAccountKeepsOneAccountAndOneFeed() throws {
        let first = try link(credentials: credentials())
        let firstFeedID = first.feed?.id
        try link(credentials: credentials(), token: "token-2")

        XCTAssertEqual(try allAccounts().count, 1)
        XCTAssertEqual(try mastodonFeeds().count, 1)
        XCTAssertEqual(try allAccounts().first?.feed?.id, firstFeedID, "De bestaande feed moet behouden blijven")
    }

    func testRelinkingClearsNeedsReauthAndStoresNewToken() throws {
        let account = try link(credentials: credentials())
        account.needsReauth = true
        try container.mainContext.save()

        let relinked = try link(
            credentials: credentials(username: "alice2", displayName: "Alice Nieuw"),
            clientID: "client-2", token: "token-2")

        XCTAssertFalse(relinked.needsReauth)
        XCTAssertEqual(relinked.username, "alice2")
        XCTAssertEqual(relinked.displayName, "Alice Nieuw")
        XCTAssertEqual(relinked.clientID, "client-2")
        XCTAssertEqual(savedTokens.last?.token, "token-2")
        XCTAssertEqual(savedTokens.last?.instanceURL, "https://example.social")
        XCTAssertEqual(savedTokens.last?.accountID, "42")
        XCTAssertEqual(relinked.feed?.title, "Alice Nieuw (@alice2@example.social)")
        XCTAssertEqual(relinked.feed?.url, "mastodon://example.social/@alice", "De feed-URL blijft ongewijzigd")
    }

    func testRelinkingAccountWithoutFeedResetsCursor() throws {
        let account = try link(credentials: credentials())
        account.lastFetchedStatusID = "1000"
        if let feed = account.feed {
            account.feed = nil
            container.mainContext.delete(feed)
        }
        try container.mainContext.save()

        let relinked = try link(credentials: credentials(), token: "token-2")

        XCTAssertNotNil(relinked.feed)
        XCTAssertNil(relinked.lastFetchedStatusID, "Een nieuwe feed moet de recente tijdlijn ophalen")
    }

    func testRelinkingAccountWithFeedKeepsCursor() throws {
        let account = try link(credentials: credentials())
        account.lastFetchedStatusID = "1000"
        try container.mainContext.save()

        let relinked = try link(credentials: credentials(), token: "token-2")

        XCTAssertEqual(relinked.lastFetchedStatusID, "1000")
    }

    func testRelinkingWithDifferentCapitalizationFindsSameAccount() throws {
        try link(instanceURL: "https://mastodon.social", credentials: credentials())
        let relinked = try link(instanceURL: "https://Mastodon.Social", credentials: credentials(), token: "token-2")

        XCTAssertEqual(try allAccounts().count, 1)
        XCTAssertEqual(try mastodonFeeds().count, 1)
        XCTAssertEqual(relinked.instanceURL, "https://mastodon.social", "Het opgeslagen adres blijft ongewijzigd")
        XCTAssertEqual(savedTokens.last?.token, "token-2")
        XCTAssertEqual(
            savedTokens.last?.instanceURL, "https://mastodon.social",
            "Het token hoort onder het opgeslagen adres, anders past de Keychain-sleutel niet meer")
    }

    func testRelinkingAccountWithoutFeedCreatesFeedInSocial() throws {
        let account = try link(credentials: credentials())
        if let feed = account.feed {
            account.feed = nil
            container.mainContext.delete(feed)
        }
        try container.mainContext.save()
        XCTAssertEqual(try mastodonFeeds().count, 0)

        let relinked = try link(credentials: credentials(), token: "token-2")

        XCTAssertEqual(try allAccounts().count, 1)
        XCTAssertEqual(try mastodonFeeds().count, 1)
        XCTAssertNotNil(relinked.feed)
        XCTAssertEqual(relinked.feed?.folder?.name, "Social")
        XCTAssertEqual(relinked.feed?.folder?.isSystem, true)
    }

    func testDifferentAccountsStaySeparate() throws {
        try link(credentials: credentials(id: "42"))
        try link(credentials: credentials(id: "43", username: "bob", displayName: "Bob"))
        try link(instanceURL: "https://other.social", credentials: credentials(id: "42"))

        XCTAssertEqual(try allAccounts().count, 3)
        XCTAssertEqual(try mastodonFeeds().count, 3)
    }
}
