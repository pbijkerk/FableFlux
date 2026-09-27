import Foundation
import NaturalLanguage
import Observation
import SwiftData
import OSLog

/// Eén bewering uit een samenvatting, gekoppeld aan de bronartikelen (FeedItem.id)
/// die de bewering onderbouwen. `sourceItemIDs` bevat altijd >= 1 stabiele id.
struct SummaryStatement: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let sourceItemIDs: [UUID]

    /// R11-borging: een bewering is onconstrueerbaar zonder tekst én >= 1 bron-id.
    /// Levert `nil` bij een lege tekst of ontbrekende bron, zodat een bronloze
    /// bewering nooit ontstaat en dus nooit gerenderd wordt.
    init?(text: String, sourceItemIDs: [UUID]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sourceItemIDs.isEmpty else { return nil }
        self.text = trimmed
        self.sourceItemIDs = sourceItemIDs
    }
}

struct TopicCluster {
    var topicName: String
    var keywords: [String]
    var items: [FeedItem]
    /// Gestructureerde beweringen met bron-ids — renderpunt voor inline bronverwijzingen.
    var statements: [SummaryStatement]
    /// Platte previewtekst (samengevoegde beweringen) voor lijstweergaven.
    var summary: String { statements.map(\.text).joined(separator: " ") }

    /// `items` opzoekbaar via id — gedeeld tussen de kaarten op Vandaag en `SummaryDetailView`
    /// voor het herleiden van bron-ids uit `SummaryStatement.sourceItemIDs`.
    var itemsByID: [UUID: FeedItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Fact-check-waarschuwing (R7)
    // Non-persistente, deterministische aggregatie (geen AI) over de fact-checks
    // van de artikelen in dit cluster. Toont niets zonder betwijfeld verdict.

    /// Fact-checkresultaten uit dit cluster met een betwijfeld verdict.
    var disputedFactChecks: [FactCheckResult] {
        items.flatMap { $0.factCheckResults }.filter(\.isDisputed)
    }

    /// True zodra minstens één artikel in dit cluster een betwijfelde bewering heeft.
    var hasDisputedClaim: Bool { !disputedFactChecks.isEmpty }

    // MARK: - Bronduiding (R4)
    // Geaggregeerde, non-persistente duiding over de distinct bronnen van dit
    // cluster. Onbekende ratings tellen niet mee en worden nooit als centrum/high
    // geraden; assen zonder bekende waarde leveren geen label (nil / lege reeks).

    /// Distinct bronfeeds van dit cluster, ontdubbeld op `feed?.id`.
    private var distinctFeeds: [Feed] {
        var seen = Set<UUID>()
        var feeds: [Feed] = []
        for feed in items.compactMap(\.feed) where seen.insert(feed.id).inserted {
            feeds.append(feed)
        }
        return feeds
    }

    /// Aantal distinct bronfeeds van dit cluster — getoond op de Vandaag-kaart.
    var sourceCount: Int { distinctFeeds.count }

    /// Bekende bias-posities van de distinct bronnen — voedt de `BiasSpectrumStrip`.
    var sourceBiasScores: [Int] {
        Array(Set(distinctFeeds.compactMap { $0.biasScore })).sorted()
    }

    /// Afgerond gemiddelde van de bekende bias-scores; nil zonder bekende scores.
    var averageBias: Int? {
        let scores = distinctFeeds.compactMap { $0.biasScore }
        guard !scores.isEmpty else { return nil }
        let mean = Double(scores.reduce(0, +)) / Double(scores.count)
        return Int(mean.rounded())
    }

    /// Afgeleid "overwegend"-label uit het gemiddelde; nil zonder bekende scores.
    var dominantBiasLabel: String? {
        guard let averageBias else { return nil }
        return "Overwegend \(biasLabel(averageBias).lowercased())"
    }

    /// Dominante (meest voorkomende) betrouwbaarheid van de distinct bronnen; bij
    /// gelijkspel de meest voorzichtige (low > mixed > high). Nil zonder bekende waarden.
    var dominantReliability: String? {
        let levels = distinctFeeds.compactMap { $0.reliabilityLevel?.lowercased() }
        guard !levels.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for level in levels { counts[level, default: 0] += 1 }
        // Lagere rang = voorzichtiger; wint bij gelijk aantal.
        let cautionRank = ["low": 0, "mixed": 1, "high": 2]
        return counts.max { a, b in
            a.value != b.value
                ? a.value < b.value
                : (cautionRank[a.key] ?? 3) > (cautionRank[b.key] ?? 3)
        }?.key
    }
}

/// Snapshot of a FeedItem's text — safe to pass across actor boundaries.
/// `id` draagt FeedItem.id zodat bron-ids stabiel zijn (geen positienummer).
/// Tevens het invoercontract richting `AnthropicClient`.
struct ItemSnapshot: Sendable {
    let id: UUID
    let title: String
    let plainDescription: String
    var fullText: String { "\(title) \(plainDescription)" }
}

@MainActor
@Observable
class TopicClusteringService {
    var isClustering = false

    /// De lopende clusteringronde. Een nieuwe aanroep annuleert deze: zijn invoer is
    /// dan verouderd (bijvoorbeeld een feed die zojuist is uitgesloten), dus zijn
    /// uitkomst mag de nieuwe niet overschrijven.
    private var activeClustering: Task<[TopicCluster]?, Never>?

    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.clustering
    )

    /// De HTTP/JSON-laag richting de Anthropic API; bewust een concrete waarde
    /// (geen protocol of injectie) tot #14 een vastgelegd antwoord nodig heeft.
    private let anthropicClient = AnthropicClient()

    private let defaultTopics: [(name: String, keywords: [String])] = [
        (
            "Artificial Intelligence",
            [
                "ai", "artificial intelligence", "machine learning", "llm",
                "chatgpt", "openai", "gpt", "neural", "deep learning", "claude",
                "gemini", "copilot", "ml", "generative", "transformer", "model",
            ]
        ),
        (
            "Technology",
            [
                "tech", "software", "hardware", "app", "code", "programming", "developer",
                "startup", "silicon valley", "computer", "digital", "cloud", "saas", "api", "platform",
            ]
        ),
        (
            "Politics",
            [
                "president", "election", "government", "congress", "senate", "democrat",
                "republican", "political", "vote", "policy", "law", "minister", "parliament", "legislation",
            ]
        ),
        (
            "Science",
            [
                "research", "study", "scientist", "discovery", "space", "nasa", "experiment",
                "physics", "biology", "climate", "environment", "gene", "medicine", "quantum",
            ]
        ),
        (
            "Business",
            [
                "market", "stock", "economy", "investment", "revenue", "profit", "startup",
                "ipo", "acquisition", "merger", "ceo", "company", "finance", "trade", "economic",
            ]
        ),
        (
            "Sports",
            [
                "game", "match", "tournament", "championship", "player", "team", "score",
                "season", "league", "win", "lose", "football", "soccer", "basketball", "tennis",
            ]
        ),
        (
            "Health",
            [
                "health", "medical", "disease", "treatment", "vaccine", "hospital", "doctor",
                "drug", "clinical", "mental health", "fda", "cancer", "virus", "pandemic",
            ]
        ),
        (
            "Entertainment",
            [
                "movie", "film", "music", "album", "artist", "celebrity", "award",
                "streaming", "netflix", "disney", "show", "series", "tv", "gaming", "game",
            ]
        ),
    ]

    /// Geeft `nil` wanneer deze ronde is verdrongen door een nieuwere of is geannuleerd.
    /// De aanroeper hoort het bestaande resultaat dan te laten staan in plaats van het
    /// met een lege of verouderde lijst te overschrijven.
    /// De artikelen die binnen het recentheidsvenster vallen. Een artikel zonder
    /// `pubDate` telt mee vanaf het moment dat het is opgehaald; een artikel zonder
    /// beide (een rij van vóór #89) valt buiten het venster, zoals het zich feitelijk
    /// ook nu al gedraagt.
    static func withinSummaryWindow(
        _ items: [FeedItem],
        window: TimeInterval = AppConfiguration.summaryWindow,
        now: Date = Date()
    ) -> [FeedItem] {
        let cutoff = summaryWindowCutoff(window: window, now: now)
        return items.filter { item in
            guard let date = item.effectiveDate else { return false }
            return date >= cutoff
        }
    }

    /// De ondergrens van het recentheidsvenster. Eén definitie voor zowel de filter in
    /// het geheugen als het predicaat hieronder, zodat die twee niet uit elkaar lopen.
    static func summaryWindowCutoff(
        window: TimeInterval = AppConfiguration.summaryWindow,
        now: Date = Date()
    ) -> Date {
        now.addingTimeInterval(-window)
    }

    /// De artikelen voor de samenvatting in één query: alleen feeds die meetellen, en
    /// alleen binnen het venster (#120). Eerder werden alle artikelen van die feeds
    /// afzonderlijk geladen en pas daarna gefilterd.
    /// Het predicaat is `effectiveDate` uitgeschreven; een rij zonder `pubDate` én
    /// `fetchedAt` valt erbuiten, net als in `withinSummaryWindow`.
    static func summaryItemsDescriptor(
        window: TimeInterval = AppConfiguration.summaryWindow,
        now: Date = Date()
    ) -> FetchDescriptor<FeedItem> {
        let cutoff = summaryWindowCutoff(window: window, now: now)
        let distantPast = Date.distantPast
        return FetchDescriptor<FeedItem>(
            predicate: #Predicate { item in
                item.feed?.includedInSummary == true
                    && (item.pubDate ?? item.fetchedAt ?? distantPast) >= cutoff
            }
        )
    }

    func cluster(
        items: [FeedItem],
        savedTopics: [Topic],
        claudeAPIKey: String?
    ) async -> [TopicCluster]? {
        // De nieuwste aanroep wint: hij kent de actuele feeds en instellingen.
        activeClustering?.cancel()

        let task = Task { [weak self] in
            await self?.performCluster(
                items: items, savedTopics: savedTopics, claudeAPIKey: claudeAPIKey
            ) ?? nil
        }
        activeClustering = task

        let result = await task.value
        if activeClustering == task {
            activeClustering = nil
            isClustering = false
        }
        return result
    }

    private func performCluster(
        items: [FeedItem],
        savedTopics: [Topic],
        claudeAPIKey: String?
    ) async -> [TopicCluster]? {
        isClustering = true

        logger.info("Starting clustering of \(items.count) items")

        // --- Lees RUWE model-velden op de MainActor (alleen stored-property-reads,
        // geen regex/HTML-strip). Het CPU-intensieve HTML-strippen naar platte tekst
        // gebeurt off-main in de detached taak hieronder, niet op de MainActor. ---
        // `cachedPlain` leest alleen de transient cache uit (strippt niets), zodat een
        // item dat al eerder gestript is niet opnieuw door de regex hoeft.
        let rawItems: [(id: UUID, title: String, rawDescription: String?, cachedPlain: String?)] = items.map {
            (id: $0.id, title: $0.title, rawDescription: $0.itemDescription, cachedPlain: $0.cachedPlainDescription)
        }

        let likedTopics = savedTopics.filter { $0.isLiked }
        let usingLikedOnly = !likedTopics.isEmpty

        var topicMap: [(name: String, keywords: [String])]
        if usingLikedOnly {
            topicMap = likedTopics.map { ($0.name, $0.keywords) }
        } else {
            topicMap = savedTopics.map { ($0.name, $0.keywords) }
            let savedNames = Set(savedTopics.map { $0.name.lowercased() })
            for dt in defaultTopics where !savedNames.contains(dt.name.lowercased()) {
                topicMap.append(dt)
            }
        }

        logger.debug("Using \(topicMap.count) topics for clustering")

        // --- Assign items to topics off the MainActor (no SwiftData access) ---
        // Alleen Sendable data (ruwe strings + topic-strings) gaat naar de detached
        // taak; het HTML-strippen, de tokenisatie en de matchloop — alle CPU-werk —
        // mogen de UI niet seconden blokkeren (IOS_Swift.md: "Task.detached voor
        // CPU-intensief werk"). De detached taak levert de (off-main gestripte)
        // snapshots terug plus de toewijzing.
        var topicKeywordsMap: [String: [String]] = [:]
        for (name, keywords) in topicMap {
            topicKeywordsMap[name] = keywords
        }

        let topicsForMatching = topicMap
        let minimumScore = AppConfiguration.minimumClusterScore
        // `Task.detached` erft géén cancellation: koppel die expliciet door, anders
        // draait de CPU-lus door nadat de aanroeper (bijv. de `.task` van een view) is
        // geannuleerd en blijft `cluster(...)` hangen met `isClustering == true`.
        let work = Task.detached {
            Self.computeAssignments(
                rawItems: rawItems,
                topics: topicsForMatching,
                minimumScore: minimumScore
            )
        }
        let assignment = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard let assignment else {
            logger.info("Clustering geannuleerd tijdens de toewijzing")
            return nil
        }
        let snapshots = assignment.snapshots
        let indexMap = assignment.indexMap

        // Warm de transient cache van de modellen met de off-main gestripte tekst;
        // anders strippen de views (lijstrijen, artikeldetail) dezelfde HTML later
        // alsnog op de MainActor. Alleen wanneer de ruwe tekst intussen niet gewijzigd
        // is, zodat de cache nooit een verouderde waarde krijgt.
        for (idx, item) in items.enumerated() where item.itemDescription == rawItems[idx].rawDescription {
            item.primePlainDescriptionCache(snapshots[idx].plainDescription)
        }

        // --- Build clusters ---
        var result: [TopicCluster] = []

        for (name, indices) in indexMap {
            guard !indices.isEmpty else { continue }

            // Nieuwste eerst, vóór het samenvatten. De samenvatting gebruikt
            // `prefix(maxArticlesPerSummary)`; zonder deze sortering is dat de volgorde
            // waarin artikelen ooit zijn opgeslagen, waardoor nieuwe artikelen bij een
            // onderwerp met meer dan tien artikelen structureel buiten de prompt vallen
            // en de samenvatting niet meer verandert (#65).
            let ordered = indices.sorted {
                (items[$0].pubDate ?? .distantPast) > (items[$1].pubDate ?? .distantPast)
            }

            let topicItems = ordered.map { items[$0] }
            let topicSnaps = ordered.map { snapshots[$0] }
            let keywords = topicKeywordsMap[name] ?? []

            let statements: [SummaryStatement]
            if let apiKey = claudeAPIKey, !apiKey.isEmpty {
                logger.debug("Generating Claude summary for topic: \(name)")
                // Pass only Sendable snapshots to async Claude call
                statements = await generateSummaryWithClaude(
                    topicName: name,
                    snapshots: topicSnaps,
                    apiKey: apiKey
                )
            } else {
                statements = localSummary(topicName: name, snapshots: topicSnaps)
            }

            result.append(
                TopicCluster(
                    topicName: name,
                    keywords: keywords,
                    items: topicItems,
                    statements: validated(statements, topicName: name)
                ))
        }

        // Verdrongen door een nieuwere ronde: die kent de actuele situatie.
        if Task.isCancelled {
            logger.info("Clustering verdrongen door een nieuwere ronde")
            return nil
        }

        logger.info("Clustering complete: created \(result.count) clusters")

        return result.sorted { $0.items.count > $1.items.count }
    }

    /// Kiest voor één (al op woordgrens getokeniseerde) artikeltekst het best
    /// scorende onderwerp. `paddedText` is de uitvoer van `wordBoundaryText`
    /// (" token token "); `normalizedTopics` bevat per onderwerp de eveneens op
    /// woordgrens omsloten frasen. Telt trefwoord-frasen op woordgrens, breekt
    /// gelijke ruwe scores op de genormaliseerde score (treffers / aantal frasen)
    /// zodat een lange trefwoordenlijst niet louter door lijstvolgorde wint, en
    /// levert alleen een onderwerp als `bestScore >= minimumScore`; anders `nil`.
    /// Instance-wrapper (bruikbaar vanuit de #38-tests) over de pure, `nonisolated`
    /// static implementatie. Bevat geen actor-state, dus vrij van de MainActor
    /// aanroepbaar — ook vanuit de detached toewijzingstaak.
    nonisolated func assignedTopic(
        forText paddedText: String,
        normalizedTopics: [(name: String, phrases: [String])],
        minimumScore: Int
    ) -> String? {
        Self.assignedTopic(
            forText: paddedText,
            normalizedTopics: normalizedTopics,
            minimumScore: minimumScore
        )
    }

    nonisolated static func assignedTopic(
        forText paddedText: String,
        normalizedTopics: [(name: String, phrases: [String])],
        minimumScore: Int
    ) -> String? {
        var bestTopic: String?
        var bestScore = 0
        var bestNormalized = 0.0

        for (name, phrases) in normalizedTopics {
            var score = 0
            for phrase in phrases where paddedText.contains(phrase) { score += 1 }
            guard score > 0 else { continue }
            // Tie-break op genormaliseerde score (treffers / aantal trefwoorden),
            // zodat een lange trefwoordenlijst niet louter door lijstvolgorde wint.
            let normalized = Double(score) / Double(max(phrases.count, 1))
            if score > bestScore || (score == bestScore && normalized > bestNormalized) {
                bestScore = score
                bestNormalized = normalized
                bestTopic = name
            }
        }

        guard bestScore >= minimumScore, let topic = bestTopic else { return nil }
        return topic
    }

    /// Voert al het CPU-werk off-main uit: strippt de ruwe beschrijvingen tot platte
    /// tekst (`FeedItem.plainText(from:)`), normaliseert de topic-frasen en scoort
    /// elke snapshot. Werkt uitsluitend op Sendable invoer (ruwe strings + topic-
    /// strings) en levert de (off-main gestripte) snapshots plus dezelfde `indexMap`
    /// (topicNaam → indices) als de oude MainActor-loop. Eén `NLTokenizer` wordt over
    /// de hele batch hergebruikt (vervangt de vroegere main-actor-stored instantie,
    /// die off-actor niet bruikbaar is).
    nonisolated private static func computeAssignments(
        rawItems: [(id: UUID, title: String, rawDescription: String?, cachedPlain: String?)],
        topics: [(name: String, keywords: [String])],
        minimumScore: Int
    ) -> (snapshots: [ItemSnapshot], indexMap: [String: [Int]])? {
        let tokenizer = NLTokenizer(unit: .word)

        // HTML-strippen off-main: de dure regex-transformatie draait hier, niet op
        // de MainActor. `plainDescription` blijft identiek aan de instance-getter;
        // een al gestripte tekst uit de cache wordt hergebruikt.
        var snapshots: [ItemSnapshot] = []
        snapshots.reserveCapacity(rawItems.count)
        for (idx, raw) in rawItems.enumerated() {
            if idx.isMultiple(of: AppConfiguration.clusteringCancellationCheckInterval), Task.isCancelled { return nil }
            snapshots.append(
                ItemSnapshot(
                    id: raw.id,
                    title: raw.title,
                    plainDescription: raw.cachedPlain ?? FeedItem.plainText(from: raw.rawDescription)
                ))
        }

        // Normaliseer trefwoorden één keer vooraf tot met-spaties-omsloten frasen
        // (" ai ", " machine learning "), zodat de match in de hot loop een simpele
        // deelstring-check op woordgrenzen is — geen regex-(her)compilatie per item.
        let normalizedTopics: [(name: String, phrases: [String])] = topics.map { topic in
            (topic.name, topic.keywords.map { wordBoundaryText($0, tokenizer: tokenizer) })
        }

        var indexMap: [String: [Int]] = [:]  // topicName → indices into `snapshots`
        for (idx, snapshot) in snapshots.enumerated() {
            if idx.isMultiple(of: AppConfiguration.clusteringCancellationCheckInterval), Task.isCancelled { return nil }
            // Eén tokenisatie per snapshot; frasen matchen alleen op woordgrenzen.
            let paddedText = wordBoundaryText(snapshot.fullText, tokenizer: tokenizer)
            if let topic = assignedTopic(
                forText: paddedText,
                normalizedTopics: normalizedTopics,
                minimumScore: minimumScore
            ) {
                indexMap[topic, default: []].append(idx)
            }
        }
        return (snapshots, indexMap)
    }

    // MARK: - Summary helpers

    /// R11-validatiegate: borgt dat elke bewering >= 1 bron-id draagt. De failable
    /// `SummaryStatement`-init maakt bronloze beweringen onmogelijk; deze gate vangt
    /// een eventuele regressie zichtbaar af (foutlog + assertie in debug) en filtert
    /// bronloze beweringen weg zodat ze in release nooit gerenderd worden.
    private func validated(_ statements: [SummaryStatement], topicName: String) -> [SummaryStatement] {
        // De failable init maakt deze tak in de praktijk onbereikbaar; hij blijft
        // opzettelijk als regressievanger voor toekomstige constructiepaden.
        let sourceless = statements.filter { $0.sourceItemIDs.isEmpty }
        guard sourceless.isEmpty else {
            logger.error("R11-schending: \(sourceless.count) bronloze bewering(en) voor topic: \(topicName)")
            assertionFailure("R11: bewering zonder bron-id in gegenereerde samenvatting")
            return statements.filter { !$0.sourceItemIDs.isEmpty }
        }
        return statements
    }

    private func currentSummaryLength() -> AppConfiguration.SummaryLength {
        let raw =
            UserDefaults.standard.string(forKey: AppConfiguration.UserDefaultsKeys.summaryLength)
            ?? AppConfiguration.defaultSummaryLength
        return AppConfiguration.SummaryLength(rawValue: raw) ?? .normaal
    }

    /// Fallback zonder AI: één bewering per bronartikel, elk gekoppeld aan zijn
    /// eigen FeedItem.id. Levert altijd >= 1 bron-id per bewering.
    private func localSummary(topicName: String, snapshots: [ItemSnapshot]) -> [SummaryStatement] {
        let length = currentSummaryLength()
        let isEnglish =
            (UserDefaults.standard.string(
                forKey: AppConfiguration.UserDefaultsKeys.summaryLanguage) ?? "nl") == "en"

        let selected = Array(snapshots.prefix(length.localSnippetCount))

        // Geen bronnen beschikbaar: één introbewering met alle ids. Zonder ids
        // levert de failable init nil en blijft de samenvatting bronloos-vrij.
        guard !selected.isEmpty else {
            let intro =
                isEnglish
                ? "Recent coverage of \(topicName) includes \(snapshots.count) article(s)."
                : "Recente berichtgeving over \(topicName) omvat \(snapshots.count) artikel(en)."
            return [SummaryStatement(text: intro, sourceItemIDs: snapshots.map(\.id))]
                .compactMap { $0 }
        }

        return selected.compactMap { s in
            let snippet = String(s.plainDescription.prefix(200))
            let text = snippet.isEmpty ? s.title : "\(s.title): \(snippet)"
            return SummaryStatement(text: text, sourceItemIDs: [s.id])
        }
    }

    /// Vraagt een AI-samenvatting op bij `AnthropicClient` en valt terug op de
    /// lokale samenvatting zodra die geen bruikbaar antwoord levert (R8). De
    /// client doet het transport; de keuze van lengte en taal blijft hier.
    private func generateSummaryWithClaude(
        topicName: String,
        snapshots: [ItemSnapshot],
        apiKey: String
    ) async -> [SummaryStatement] {
        let length = currentSummaryLength()
        let isEnglish =
            (UserDefaults.standard.string(
                forKey: AppConfiguration.UserDefaultsKeys.summaryLanguage) ?? "nl") == "en"

        let statements = await anthropicClient.generateSummary(
            topicName: topicName,
            snapshots: snapshots,
            apiKey: apiKey,
            length: length,
            isEnglish: isEnglish
        )
        return statements ?? localSummary(topicName: topicName, snapshots: snapshots)
    }

    /// Tokeniseert `text` op woordgrenzen (Apple `NLTokenizer`, consistent met
    /// `extractKeywords`) en levert de kleingeletterde tokens aaneengeregen met
    /// spaties, omsloten door één spatie aan begin en eind: " token token token ".
    /// Zo matcht een trefwoord alleen als heel woord/hele frase — een deelstring
    /// als "ai" in "email" valt weg omdat " ai " niet in " email " voorkomt.
    /// Instance-wrapper (bruikbaar vanuit de #38-tests) met een eigen tokenizer per
    /// aanroep. De clustering-hotloop gebruikt de static variant met een over de
    /// batch hergebruikte tokenizer; deze wrapper is `nonisolated` en dus vrij van
    /// de MainActor aanroepbaar.
    nonisolated func wordBoundaryText(_ text: String) -> String {
        Self.wordBoundaryText(text, tokenizer: NLTokenizer(unit: .word))
    }

    nonisolated static func wordBoundaryText(_ text: String, tokenizer: NLTokenizer) -> String {
        let lower = text.lowercased()
        tokenizer.string = lower
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: lower.startIndex..<lower.endIndex) { range, _ in
            tokens.append(String(lower[range]))
            return true
        }
        return " " + tokens.joined(separator: " ") + " "
    }

    func extractKeywords(from text: String, limit: Int = 10) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text.lowercased()

        let stopWords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of",
            "with", "by", "from", "is", "was", "are", "were", "be", "been", "have", "has",
            "had", "do", "does", "did", "will", "would", "could", "should", "may", "might",
            "this", "that", "these", "those", "it", "its",
        ])
        var wordCounts: [String: Int] = [:]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if let tag, tag == .noun || tag == .adjective {
                let word = String(text[range]).lowercased()
                if word.count > 3, !stopWords.contains(word) {
                    wordCounts[word, default: 0] += 1
                }
            }
            return true
        }

        return wordCounts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }
}
