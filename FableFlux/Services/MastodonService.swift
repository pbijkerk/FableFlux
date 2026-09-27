import Foundation
import SwiftData
import OSLog

// MARK: - Mastodon API Codable structs

struct MastodonStatus: Codable {
    let id: String
    let createdAt: Date
    let url: String?
    let content: String
    let reblog: MastodonStatusReblog?
    let account: MastodonStatusAccount
    let mediaAttachments: [MastodonMediaAttachment]
    let spoilerText: String
}

/// Afzonderlijk type voor reblog om recursief Codable-probleem te vermijden
struct MastodonStatusReblog: Codable {
    let id: String
    let createdAt: Date
    let url: String?
    let content: String
    let account: MastodonStatusAccount
    let mediaAttachments: [MastodonMediaAttachment]
    let spoilerText: String
}

struct MastodonStatusAccount: Codable {
    let id: String
    let username: String
    let displayName: String
    let avatar: String
}

struct MastodonMediaAttachment: Codable {
    let type: String
    let url: String
    let previewUrl: String?
}

struct MastodonAppRegistration: Codable {
    let clientId: String
    let clientSecret: String
}

struct MastodonToken: Codable {
    let accessToken: String
    let tokenType: String
}

struct MastodonVerifyCredentials: Codable {
    let id: String
    let username: String
    let displayName: String
    let avatar: String
}

// MARK: - Mastodon fouttypen

enum MastodonError: LocalizedError {
    case invalidInstance(String)
    case oauthCancelled
    case oauthFailed(String)
    case tokenExchangeFailed(String)
    case credentialVerificationFailed(String)
    case timelineFetchFailed(String)
    case httpError(statusCode: Int, body: String)
    case decodingFailed(underlying: Error)
    case noAccountForFeed

    var errorDescription: String? {
        switch self {
        case .invalidInstance(let url): return "Ongeldig instantie-adres: \(url)"
        case .oauthCancelled: return "Inloggen geannuleerd"
        case .oauthFailed(let msg): return "OAuth mislukt: \(msg)"
        case .tokenExchangeFailed(let msg): return "Toegangstoken ophalen mislukt: \(msg)"
        case .credentialVerificationFailed(let m): return "Account verifiëren mislukt: \(m)"
        case .timelineFetchFailed(let msg): return "Timeline ophalen mislukt: \(msg)"
        case .httpError(let code, _): return "Serverfout (HTTP \(code))"
        case .decodingFailed: return "Onverwacht serverantwoord"
        case .noAccountForFeed: return "Geen Mastodon-account gekoppeld aan deze feed"
        }
    }
}

// MARK: - MastodonService

class MastodonService {

    static let shared = MastodonService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let redirectURI = "rssreader://oauth/mastodon"
    private let scope = "read"
    private let appName = "FableFlux"

    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.mastodon
    )

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let short = ISO8601DateFormatter()
        short.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = full.date(from: str) { return date }
            if let date = short.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Ongeldige datumnotatie: \(str)")
        }
    }

    // MARK: - App registratie

    func registerApp(instanceURL: String) async throws -> MastodonAppRegistration {
        logger.debug("Registering app with instance: \(instanceURL)")

        guard let base = URL(string: instanceURL) else {
            throw MastodonError.invalidInstance(instanceURL)
        }
        let url = base.appendingPathComponent("api/v1/apps")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_name": appName,
            "redirect_uris": redirectURI,
            "scopes": scope,
            "website": "",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try checkHTTP(response, data: data)

        let registration = try decodeOrThrow(MastodonAppRegistration.self, from: data)
        logger.info("App registration successful")

        return registration
    }

    // MARK: - OAuth

    func buildAuthorizeURL(instanceURL: String, clientID: String) throws -> URL {
        guard var components = URLComponents(string: instanceURL) else {
            throw MastodonError.invalidInstance(instanceURL)
        }
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "force_login", value: "false"),
        ]
        guard let url = components.url else {
            throw MastodonError.invalidInstance(instanceURL)
        }
        return url
    }

    func exchangeToken(
        instanceURL: String, clientID: String,
        clientSecret: String, code: String
    ) async throws -> MastodonToken {
        guard let base = URL(string: instanceURL) else {
            throw MastodonError.invalidInstance(instanceURL)
        }
        let url = base.appendingPathComponent("oauth/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "scope": scope,
        ]
        request.httpBody =
            params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try checkHTTP(response, data: data)
        return try decodeOrThrow(MastodonToken.self, from: data)
    }

    func verifyCredentials(instanceURL: String, accessToken: String) async throws -> MastodonVerifyCredentials {
        guard let base = URL(string: instanceURL) else {
            throw MastodonError.invalidInstance(instanceURL)
        }
        let url = base.appendingPathComponent("api/v1/accounts/verify_credentials")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try checkHTTP(response, data: data)
        return try decodeOrThrow(MastodonVerifyCredentials.self, from: data)
    }

    // MARK: - Home timeline

    func fetchHomeTimeline(
        account: MastodonAccount,
        sinceID: String? = nil
    ) async throws -> [MastodonStatus] {
        guard var components = URLComponents(string: account.instanceURL) else {
            throw MastodonError.invalidInstance(account.instanceURL)
        }
        components.path = "/api/v1/timelines/home"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let sinceID {
            items.append(URLQueryItem(name: "min_id", value: sinceID))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw MastodonError.invalidInstance(account.instanceURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(resolveToken(for: account))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try checkHTTP(response, data: data)
        return try decodeOrThrow([MastodonStatus].self, from: data)
    }

    // MARK: - Status → FeedItem mapping

    func mapToFeedItem(status: MastodonStatus, feed: Feed) -> FeedItem {
        let item = FeedItem(
            title: buildTitle(status),
            link: status.url,
            itemDescription: buildContent(status),
            pubDate: status.createdAt,
            guid: status.id,
            enclosureURL: nil,
            enclosureMIMEType: nil
        )
        item.feed = feed

        // Bij boosts zitten de bijlagen op het originele bericht
        let attachments = status.reblog?.mediaAttachments ?? status.mediaAttachments
        let images = attachments.filter { $0.type == "image" }

        // Eerste afbeelding als enclosure én thumbnail
        if let first = images.first {
            item.enclosureURL = first.url
            item.enclosureMIMEType = mimeType(from: first.url)
            item.imageURL = first.previewUrl ?? first.url
        }

        // Alle afbeeldingen toevoegen aan de HTML-content (zichtbaar in detailweergave)
        if !images.isEmpty {
            let imgHTML = images.map { img in
                "<img src=\"\(escape(img.url))\" alt=\"\" style=\"max-width:100%;border-radius:8px;margin:8px 0;display:block;\">"
            }.joined(separator: "\n")
            item.itemDescription = (item.itemDescription ?? "") + "\n" + imgHTML
        }

        return item
    }

    private func buildTitle(_ status: MastodonStatus) -> String {
        if let reblog = status.reblog {
            return "\(status.account.displayName) ↩ \(reblog.account.displayName)"
        }
        return status.account.displayName
    }

    private func buildContent(_ status: MastodonStatus) -> String {
        if let reblog = status.reblog {
            let header = "<p><strong>\(escape(status.account.displayName))</strong> boosted:</p>"
            return header + wrapCW(reblog.spoilerText, content: reblog.content)
        }
        return wrapCW(status.spoilerText, content: status.content)
    }

    private func wrapCW(_ cw: String, content: String) -> String {
        guard !cw.isEmpty else { return content }
        return "<details><summary><strong>CW: \(escape(cw))</strong></summary>\(content)</details>"
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Leidt het MIME-type af uit de bestandsextensie van de URL; nil als die onbekend is.
    private func mimeType(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        default: return nil
        }
    }

    // MARK: - Feed refresh

    @MainActor
    func refreshFeed(account: MastodonAccount, feed: Feed, context: ModelContext) async throws {
        logger.debug("Refreshing Mastodon feed for: \(account.username)@\(account.instanceURL)")

        let statuses = try await fetchHomeTimeline(account: account, sinceID: account.lastFetchedStatusID)

        guard !statuses.isEmpty else {
            logger.debug("No new statuses for \(account.username)")
            return
        }

        logger.info("Fetched \(statuses.count) new statuses for \(account.username)")

        let existingGUIDs = Set(
            FeedRefreshService.existingKeys(of: feed, context: context).compactMap { $0.guid }
        )
        var newItems: [FeedItem] = []

        for status in statuses where !existingGUIDs.contains(status.id) {
            let item = mapToFeedItem(status: status, feed: feed)
            context.insert(item)
            newItems.append(item)
        }
        // Eén append, zodat schermen die `feed.items` tonen bijwerken (zie `existingKeys`).
        if !newItems.isEmpty {
            feed.items.append(contentsOf: newItems)
        }

        logger.debug("Added \(newItems.count) new items to feed")

        // Cursor naar meest recente status (index 0 = nieuwste)
        if let newestID = statuses.first?.id {
            account.lastFetchedStatusID = newestID
        }
        account.lastRefreshed = Date()
        account.needsReauth = false
        feed.lastRefreshed = Date()

        // Bewaarperiode toepassen
        FeedRefreshService.pruneOldItems(feed: feed, context: context)

        try context.save()
    }

    // MARK: - Token helpers

    /// Slaat een Mastodon-token veilig op in de Keychain.
    /// Aanroepen vanuit de Views-laag zodat KeychainService buiten Models/Views blijft.
    func saveToken(_ token: String, instanceURL: String, accountID: String) {
        let key = AppConfiguration.KeychainKeys.mastodonToken(instanceURL: instanceURL, accountID: accountID)
        KeychainService.save(token, forKey: key)
    }

    /// Geeft de toegangstoken terug: Keychain heeft prioriteit (veilig),
    /// met terugval op de waarde in SwiftData voor accounts vóór de migratie.
    private func resolveToken(for account: MastodonAccount) -> String {
        let key = AppConfiguration.KeychainKeys.mastodonToken(
            instanceURL: account.instanceURL,
            accountID: account.accountID
        )
        return KeychainService.load(forKey: key) ?? account.accessToken
    }

    // MARK: - HTTP helpers

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:
            throw MastodonError.httpError(
                statusCode: 401,
                body: String(data: data, encoding: .utf8) ?? "")
        case 403: throw MastodonError.oauthFailed("Onvoldoende rechten (403)")
        case 404: throw MastodonError.invalidInstance("Endpoint niet gevonden (404)")
        case 429: throw MastodonError.timelineFetchFailed("Te veel verzoeken — probeer later opnieuw")
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MastodonError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MastodonError.decodingFailed(underlying: error)
        }
    }
}
