import Foundation

/// Singleton die de OAuth-callback opvangt en doorstuurt naar de wachtende async-aanroep.
/// @MainActor garandeert thread-safe toegang tot de mutable continuation.
@MainActor
class OAuthCallbackHandler {
    static let shared = OAuthCallbackHandler()
    private init() {}

    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    /// Registreert een wachtende continuation. Annuleert een eventuele vorige flow.
    func setPendingContinuation(_ continuation: CheckedContinuation<String, Error>) {
        // Bestaande flow afbreken als die nog loopt (defensief)
        finish(throwing: MastodonError.oauthCancelled)

        pendingContinuation = continuation

        // Veiligheidstimeout: annuleer na 5 minuten als callback uitblijft
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard let self, !Task.isCancelled else { return }
            self.finish(throwing: MastodonError.oauthFailed("OAuth-sessie verlopen"))
        }
    }

    /// Verwerkt een inkomende URL (aangeroepen vanuit ContentView.onOpenURL).
    func handle(url: URL) {
        guard url.scheme == "rssreader" else { return }

        // Geef SafariBrowserView het signaal om te sluiten
        NotificationCenter.default.post(name: .oauthCallbackReceived, object: nil)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            finish(throwing: MastodonError.oauthFailed("Geen autorisatiecode ontvangen"))
            return
        }

        finish(returning: code)
    }

    /// Annuleert de wachtende OAuth-aanvraag (gebruiker sluit browser handmatig).
    func cancel() {
        finish(throwing: MastodonError.oauthCancelled)
    }

    // MARK: - Privé helpers

    private func finish(returning value: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingContinuation?.resume(returning: value)
        pendingContinuation = nil
    }

    private func finish(throwing error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
    }
}

extension Notification.Name {
    static let oauthCallbackReceived = Notification.Name("nl.rssreader.oauthCallbackReceived")
}
