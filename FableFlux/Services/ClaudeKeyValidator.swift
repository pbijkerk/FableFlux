import Foundation
import OSLog

/// Lichte validatie van een Claude API-sleutel tegen de Anthropic API.
///
/// Doet een goedkope `GET /v1/models` (geen tokenkosten, in tegenstelling tot
/// een `/v1/messages`-POST) en leidt uit de HTTP-statuscode af of de sleutel
/// geldig is. De sleutel gaat uitsluitend via de `x-api-key`-header, nooit in
/// de URL of in logregels.
enum ClaudeKeyValidator {

    /// Uitkomst van een validatiepoging.
    enum Result: Equatable {
        /// De sleutel is geldig (HTTP 200).
        case valid
        /// De sleutel is ongeldig of verlopen (HTTP 401/403).
        case invalid
        /// Kon niet valideren (netwerkfout of onverwachte statuscode) — geen foutkleur tonen.
        case couldNotValidate
    }

    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.networking
    )

    private static let modelsURL = URL(string: "https://api.anthropic.com/v1/models")

    /// Valideert de opgegeven sleutel met een lichte `GET /v1/models`-call.
    ///
    /// - Parameter apiKey: de te valideren Claude API-sleutel.
    /// - Returns: `.valid` bij 200, `.invalid` bij 401/403, anders `.couldNotValidate`.
    static func validate(apiKey: String) async -> Result {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = modelsURL else {
            return .couldNotValidate
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Nooit uit de URLCache beantwoorden: de cache-sleutel is de URL, niet de
        // x-api-key-header, dus een gewijzigde (ongeldige) sleutel zou anders de
        // gecachete 200 van een eerdere geldige sleutel terugkrijgen.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConfiguration.networkTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                logger.error("Sleutelvalidatie: geen HTTP-response ontvangen")
                return .couldNotValidate
            }

            switch http.statusCode {
            case 200:
                logger.info("Sleutelvalidatie: sleutel geldig")
                return .valid
            case 401, 403:
                logger.info("Sleutelvalidatie: sleutel ongeldig (status \(http.statusCode))")
                return .invalid
            default:
                logger.error("Sleutelvalidatie: onverwachte status \(http.statusCode)")
                return .couldNotValidate
            }
        } catch {
            logger.error("Sleutelvalidatie mislukt: \(error.localizedDescription)")
            return .couldNotValidate
        }
    }
}
