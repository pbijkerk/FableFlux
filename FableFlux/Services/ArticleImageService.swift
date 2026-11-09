import Foundation
import ImageIO
import Network
import OSLog
import SwiftData
import UIKit

/// Wanneer de app nieuwe afbeeldingen mag downloaden (#225).
enum ImageLoadPolicy: String, CaseIterable, Identifiable {
    case always
    case wifiOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: return "Altijd"
        case .wifiOnly: return "Alleen via wifi"
        }
    }

    static var current: ImageLoadPolicy {
        UserDefaults.standard.string(forKey: AppConfiguration.UserDefaultsKeys.imageLoadPolicy)
            .flatMap(ImageLoadPolicy.init(rawValue:)) ?? .always
    }

    /// Of er nu over het netwerk geladen mag worden. Gecachte afbeeldingen mogen altijd.
    static func allowsNetwork(policy: ImageLoadPolicy, onExpensiveNetwork: Bool) -> Bool {
        policy == .always || !onExpensiveNetwork
    }
}

/// Houdt bij of het toestel op een duur netwerk zit (mobiel netwerk of persoonlijke hotspot).
final class NetworkStatus: @unchecked Sendable {
    static let shared = NetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            // `isExpensive` dekt mobiel netwerk én een hotspot via de iPhone; een
            // cellular-interface telt ook als duur als iOS dat (nog) niet zo markeert.
            self.expensive = path.isExpensive || path.usesInterfaceType(.cellular)
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "nl.fableflux.network-status"))
    }

    var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expensive
    }
}

/// Afbeeldingen voor de artikellijst (#225): een eigen schijfcache, verkleinen buiten de
/// main thread, minimale afmeting, en `og:image` van de artikelpagina als de feed zelf geen
/// afbeelding meegeeft.
final class ArticleImageService: @unchecked Sendable {
    static let shared = ArticleImageService()

    /// Kleiner dan dit (in pixels, breedte of hoogte) is een icoon, logo of trackerpixel.
    static let minimumDimension = 200
    /// Grootste kant na verkleinen: scherp genoeg voor een kaart van schermbreedte.
    static let maximumPixelSize = 1200

    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.extraction
    )

    private let session: URLSession
    private let memory = NSCache<NSURL, UIImage>()
    /// URL's waarvan al vaststaat dat ze te klein of onbruikbaar zijn.
    private var rejected = Set<URL>()
    private let lock = NSLock()

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ArticleImages", isDirectory: true)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: cacheDir)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
        memory.countLimit = 150
    }

    // MARK: - Afbeelding laden

    /// Laadt, verkleint en cachet een afbeelding. `nil` als hij te klein is, niet geladen
    /// mag worden (alleen via wifi) of mislukt.
    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if isRejected(url) { return nil }

        let allowNetwork = ImageLoadPolicy.allowsNetwork(
            policy: .current, onExpensiveNetwork: NetworkStatus.shared.isExpensive)
        var request = URLRequest(url: url)
        // Op een duur netwerk met "alleen via wifi": alleen wat al in de cache staat.
        request.cachePolicy = allowNetwork ? .returnCacheDataElseLoad : .returnCacheDataDontLoad

        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            reject(url)
            return nil
        }
        guard let image = Self.downsample(data, maxPixelSize: Self.maximumPixelSize) else {
            reject(url)
            return nil
        }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Verkleint met ImageIO zonder het volle beeld te decoderen, en weigert te kleine
    /// beelden. Puur en `static`, zodat het los te testen is.
    static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            isLargeEnough(width: width, height: height)
        else { return nil }
        let thumbOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func isLargeEnough(width: Int, height: Int) -> Bool {
        width >= minimumDimension && height >= minimumDimension
    }

    private func isRejected(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected.contains(url)
    }

    private func reject(_ url: URL) {
        lock.lock()
        rejected.insert(url)
        lock.unlock()
    }

    // MARK: - og:image van de artikelpagina

    /// Hoeveel van de pagina wordt gelezen: de meta-tags staan in de `<head>`.
    static let pageReadLimit = 300 * 1024

    /// Zoekt op de artikelpagina naar een afbeelding als de feed er geen gaf. Eén keer per
    /// artikel (`imageLookedUpAt`), en alleen als er geladen mag worden.
    @MainActor
    func lookUpImageIfNeeded(for item: FeedItem, context: ModelContext) async {
        guard item.imageURL == nil, item.imageLookedUpAt == nil, !item.isVideoItem, !item.isAudioItem,
            item.feed?.isMastodonFeed != true,
            let link = item.link, let pageURL = URL(string: link), pageURL.scheme?.hasPrefix("http") == true,
            ImageLoadPolicy.allowsNetwork(policy: .current, onExpensiveNetwork: NetworkStatus.shared.isExpensive)
        else { return }

        // `nil` = de pagina kon niet worden gelezen (offline, weggescrold, fout): dan niet
        // als "gezocht" markeren, zodat het later opnieuw kan.
        guard let result = await Self.fetchPageImageURL(pageURL, session: session), !Task.isCancelled,
            item.modelContext != nil  // intussen opgeruimd
        else { return }
        let found = result.imageURL
        item.imageLookedUpAt = Date()
        if let found {
            if Self.isSiteWideImage(found, feedID: item.feed?.id, excluding: item.id, context: context) {
                // Dezelfde afbeelding als bij een ander artikel van deze bron: dat is een
                // standaardbeeld van de site (logo, deelplaatje), geen artikelbeeld. Ook bij
                // het eerdere artikel weghalen; dat krijgt dan een tekstkaart.
                Self.clearLookedUpImage(found, feedID: item.feed?.id, context: context)
            } else {
                item.imageURL = found
            }
        }
        context.saveOrLog("de gevonden afbeelding van het artikel te bewaren")
    }

    @MainActor
    private static func isSiteWideImage(_ url: String, feedID: UUID?, excluding id: UUID, context: ModelContext)
        -> Bool
    {
        guard let feedID else { return false }
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { $0.feed?.id == feedID && $0.imageURL == url && $0.id != id })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Alleen beelden die de app zelf via de artikelpagina vond (`imageLookedUpAt`); een
    /// afbeelding uit de feed zelf blijft staan.
    @MainActor
    private static func clearLookedUpImage(_ url: String, feedID: UUID?, context: ModelContext) {
        guard let feedID else { return }
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { $0.feed?.id == feedID && $0.imageURL == url && $0.imageLookedUpAt != nil })
        for other in (try? context.fetch(descriptor)) ?? [] { other.imageURL = nil }
    }

    struct PageLookup { let imageURL: String? }

    private static func fetchPageImageURL(_ pageURL: URL, session: URLSession) async -> PageLookup? {
        var request = URLRequest(url: pageURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
        // Wel een antwoord, maar geen pagina (404, betaalmuur): gezocht, niets gevonden.
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            return PageLookup(imageURL: nil)
        }
        var data = Data()
        data.reserveCapacity(64 * 1024)
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= pageReadLimit { break }
                // De head is genoeg: stop zodra de body begint.
                if data.count % 4096 == 0, data.range(of: Data("</head>".utf8)) != nil { break }
            }
        } catch {
            return nil
        }
        let html = String(decoding: data, as: UTF8.self)
        let base = response.url ?? pageURL
        return PageLookup(imageURL: pageImageURL(fromHTML: html, baseURL: base))
    }

    /// Haalt `og:image` (of `og:image:secure_url`, `twitter:image`) uit HTML. Puur, zodat
    /// het met vaste HTML te testen is. Relatieve URL's worden opgelost tegen `baseURL`;
    /// trackers en duidelijke iconen vallen af.
    static func pageImageURL(fromHTML html: String, baseURL: URL) -> String? {
        let metas = metaTagRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var candidates: [String: String] = [:]
        for match in metas {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                let content = attribute("content", in: tag), !content.isEmpty
            else { continue }
            let lowered = key.lowercased()
            if candidates[lowered] == nil { candidates[lowered] = content }
        }
        let order = ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"]
        for key in order {
            guard let raw = candidates[key] else { continue }
            let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
                url.scheme == "https" || url.scheme == "http",
                !looksLikeTrackerOrIcon(url.absoluteString)
            else { continue }
            return url.absoluteString
        }
        return nil
    }

    static func looksLikeTrackerOrIcon(_ url: String) -> Bool {
        let lower = url.lowercased()
        let patterns = ["1x1", "pixel", "tracker", "favicon", "apple-touch-icon", "spacer.gif"]
        if patterns.contains(where: { lower.contains($0) }) { return true }
        let path = URL(string: lower)?.path ?? lower
        if path.hasSuffix(".ico") || path.hasSuffix(".svg") { return true }
        // Standaardbeelden van de site in plaats van een artikelbeeld.
        let file = (path as NSString).lastPathComponent
        return ["logo", "default", "placeholder", "fallback"].contains { file.contains($0) }
    }

    private static let metaTagRegex = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive])

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}
