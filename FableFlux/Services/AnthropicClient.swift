import Foundation
import OSLog

/// HTTP/JSON-laag voor de Anthropic Messages API: bouwt het verzoek voor één
/// onderwerp, voert de aanroep uit en parseert het antwoord naar beweringen met
/// bron-ids.
///
/// Bewust alleen transport en formaat — geen beleid. Welke samenvattingslengte en
/// taal gelden, en wat er gebeurt als er geen samenvatting komt (de terugval op de
/// lokale samenvatting, R8), blijft bij `TopicClusteringService`. Daarom levert
/// `generateSummary` `nil` bij een ontbrekend of onbruikbaar antwoord in plaats van
/// zelf een alternatief te verzinnen.
struct AnthropicClient {
    private static let endpoint = "https://api.anthropic.com/v1/messages"
    private static let model = "claude-haiku-4-5-20251001"
    private static let apiVersion = "2023-06-01"

    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.clustering
    )

    // MARK: - Request/response-JSON

    private struct Msg: Encodable {
        let role: String
        let content: String
    }
    private struct Req: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Msg]
    }
    private struct RCnt: Decodable { let text: String }
    private struct Res: Decodable { let content: [RCnt] }

    // MARK: - Aanroep

    /// Vraagt een samenvatting voor één onderwerp op.
    ///
    /// Levert `nil` wanneer er geen bruikbaar antwoord is (ongeldige URL, HTTP-fout,
    /// leeg antwoord, onparseerbaar antwoord of een netwerkfout). De aanroeper valt
    /// dan terug op de lokale samenvatting, zodat de feeds leesbaar blijven zonder
    /// werkende AI (R8).
    func generateSummary(
        topicName: String,
        snapshots: [ItemSnapshot],
        apiKey: String,
        length: AppConfiguration.SummaryLength,
        isEnglish: Bool
    ) async -> [SummaryStatement]? {
        // Beperk tot de eerste N artikelen (kostenkader R9); bewaar deze snapshots
        // zodat het 1-based bronnummer dat Claude teruggeeft naar FeedItem.id te
        // mappen is.
        let usedSnapshots = Array(snapshots.prefix(AppConfiguration.maxArticlesPerSummary))
        let prompt = Self.prompt(
            topicName: topicName,
            snapshots: usedSnapshots,
            length: length,
            isEnglish: isEnglish
        )

        guard let url = URL(string: Self.endpoint) else {
            logger.error("Invalid Claude API URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            request.httpBody = try JSONEncoder().encode(
                Req(
                    model: Self.model,
                    max_tokens: length.maxTokens,
                    messages: [Msg(role: "user", content: prompt)]
                )
            )
            let (data, httpResponse) = try await URLSession.shared.data(for: request)

            guard let http = httpResponse as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                let code = (httpResponse as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Claude API returned status \(code) for topic: \(topicName)")
                return nil
            }

            let response = try JSONDecoder().decode(Res.self, from: data)

            guard let rawText = response.content.first?.text else {
                logger.warning("Empty Claude response for topic: \(topicName)")
                return nil
            }

            let statements = Self.parseStatements(from: rawText, snapshots: usedSnapshots)
            guard !statements.isEmpty else {
                logger.warning("No usable statements decoded for topic: \(topicName)")
                return nil
            }

            logger.info("Claude summary generated for \(topicName): \(statements.count) statement(s)")
            return statements
        } catch {
            logger.error("Claude API call failed for \(topicName): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt

    /// Stelt de prompt samen uit de (al begrensde) artikelen. Ongewijzigd overgenomen
    /// uit `TopicClusteringService`; inhoudelijke wijzigingen aan de prompt of het
    /// antwoordformaat horen bij #14.
    private static func prompt(
        topicName: String,
        snapshots: [ItemSnapshot],
        length: AppConfiguration.SummaryLength,
        isEnglish: Bool
    ) -> String {
        let articleList =
            snapshots
            .enumerated()
            .map { idx, s in
                let desc = String(s.plainDescription.prefix(300))
                return "[\(idx + 1)] Title: \(s.title)\(desc.isEmpty ? "" : "\n    Description: \(desc)")"
            }
            .joined(separator: "\n\n")

        let instruction = isEnglish ? length.sentenceInstruction.en : length.sentenceInstruction.nl

        // Elk aangeboden artikel is een distinct bron. Bij >= 2 bronnen stuurt de
        // prompt expliciet op synthese: de belangrijkste beweringen leiden met door
        // meerdere bronnen bevestigde ontwikkelingen (meerdere bron-ids). Enkelvoudige
        // bronnen blijven geldig — er wordt niet gefilterd op bronaantal (R10/R11).
        let synthesisGuidance =
            snapshots.count >= 2
            ? """
            Multiple sources are available for this topic. Lead with the most \
            important developments that are confirmed by two OR MORE of the \
            articles above, and cite ALL their source numbers together (e.g. \
            [1,2]) so each such statement carries multiple source numbers. \
            Prioritise these corroborated developments first. Still include \
            noteworthy details that appear in only a single article, citing that \
            one source number — never drop a single-source item.
            """
            : """
            Only one source is available for this topic, so cite that single \
            source number for every statement.
            """

        return """
            You are summarizing news articles grouped by topic. The topic is: "\(topicName)"

            Each article is prefixed with a bracketed source number, e.g. [1], [2].

            Here are the articles:
            \(articleList)

            \(instruction)

            Break the summary into individual statements. Synthesize across articles: \
            when a statement is supported by multiple articles, cite ALL the relevant \
            source numbers; when it comes from a single article, cite only that one \
            number. \(synthesisGuidance) Every statement MUST cite at least one source \
            number of the article(s) it is based on. Do not invent source numbers; only \
            use numbers that appear above.

            Respond with ONLY a JSON object, no prose and no markdown fences, in exactly \
            this shape:
            {"statements":[{"text":"<one sentence>","sources":[1,2]}]}
            """
    }

    // MARK: - Antwoord parsen

    /// Decodeert Claude's JSON-respons naar beweringen en mapt de 1-based
    /// bronnummers naar stabiele FeedItem.id's. Beweringen zonder geldige bron
    /// worden weggelaten zodat elke bewering >= 1 bron-id houdt.
    static func parseStatements(
        from rawText: String,
        snapshots: [ItemSnapshot]
    ) -> [SummaryStatement] {
        struct ClaudeStatement: Decodable {
            let text: String
            let sources: [Int]
        }
        struct ClaudeSummary: Decodable { let statements: [ClaudeStatement] }

        // Verwijder eventuele markdown-fences en isoleer het JSON-object.
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = cleaned.firstIndex(of: "{"),
            let end = cleaned.lastIndex(of: "}")
        else {
            return []
        }
        let jsonSlice = String(cleaned[start...end])

        guard let data = jsonSlice.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(ClaudeSummary.self, from: data)
        else {
            return []
        }

        return decoded.statements.compactMap { st -> SummaryStatement? in
            // 1-based bronnummer → FeedItem.id; ongeldige nummers negeren.
            let ids = st.sources.compactMap { num -> UUID? in
                let idx = num - 1
                guard snapshots.indices.contains(idx) else { return nil }
                return snapshots[idx].id
            }
            // Failable init weigert lege tekst of ontbrekende bron (R11).
            return SummaryStatement(text: st.text, sourceItemIDs: ids)
        }
    }
}
