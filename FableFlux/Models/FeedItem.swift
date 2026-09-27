import SwiftData
import Foundation

@Model
class FeedItem {
    var id: UUID
    var title: String
    var link: String?
    var itemDescription: String?
    var pubDate: Date?
    var isRead: Bool
    var isSaved: Bool = false
    var guid: String?
    var enclosureURL: String?
    var enclosureMIMEType: String?
    var imageURL: String?
    var feed: Feed?
    @Relationship(deleteRule: .cascade) var factCheckResults: [FactCheckResult] = []
    var factCheckCheckedAt: Date?  // nil = nooit gecontroleerd

    /// Wanneer dit artikel is opgehaald. Terugval voor `pubDate`, die uit de feed komt
    /// en leeg kan zijn: zonder eigen stempel veroudert een datumloos artikel nooit,
    /// waardoor het buiten elk venster valt én nooit wordt opgeruimd (#89).
    /// `nil` bij rijen van vóór deze wijziging; die blijven zich gedragen als voorheen.
    var fetchedAt: Date?

    // Transient cache — niet bewaard, opnieuw berekend na SwiftData fault
    @Transient private var _cachedPlainDescription: String? = nil

    init(
        title: String,
        link: String? = nil,
        itemDescription: String? = nil,
        pubDate: Date? = nil,
        guid: String? = nil,
        enclosureURL: String? = nil,
        enclosureMIMEType: String? = nil,
        imageURL: String? = nil,
        fetchedAt: Date? = Date()
    ) {
        self.id = UUID()
        self.fetchedAt = fetchedAt
        self.title = title
        self.link = link
        self.itemDescription = itemDescription
        self.pubDate = pubDate
        self.isRead = false
        self.guid = guid
        self.enclosureURL = enclosureURL
        self.enclosureMIMEType = enclosureMIMEType
        self.imageURL = imageURL
    }

    /// De leeftijd waarop de app dit artikel beoordeelt: de publicatiedatum, en anders
    /// het moment van ophalen. `nil` bij rijen van vóór #89 die geen van beide hebben.
    var effectiveDate: Date? { pubDate ?? fetchedAt }

    var plainDescription: String {
        if let cached = _cachedPlainDescription { return cached }
        let result = Self.plainText(from: itemDescription)
        _cachedPlainDescription = result
        return result
    }

    /// De al gestripte tekst uit de transient cache, of `nil` zolang die leeg is.
    /// Anders dan `plainDescription` voert dit géén strip-transformatie uit; bedoeld
    /// om op de MainActor goedkoop te kunnen zien of het dure werk al gedaan is.
    var cachedPlainDescription: String? { _cachedPlainDescription }

    /// Vult de transient cache met tekst die elders (off-main) uit dezelfde ruwe
    /// beschrijving is gestript, zodat de views `plainDescription` niet alsnog op de
    /// MainActor hoeven te berekenen. De aanroeper borgt dat `value` bij de huidige
    /// `itemDescription` hoort.
    func primePlainDescriptionCache(_ value: String) {
        _cachedPlainDescription = value
    }

    /// Strippt HTML uit ruwe beschrijvingstekst tot platte tekst. `nonisolated` en
    /// puur (leest geen model-state) zodat het off-main aangeroepen kan worden —
    /// de clustering-hotloop doet dit strippen in een detached taak i.p.v. op de
    /// MainActor. Stappen identiek aan de vroegere inline `plainDescription`-logica:
    /// tags → spatie, whitespace → één spatie, trim, dan HTML-entiteiten decoderen.
    /// Gebruikt gecachte `NSRegularExpression`s (geen per-aanroep regex-compilatie).
    nonisolated static func plainText(from raw: String?) -> String {
        guard let desc = raw, !desc.isEmpty else { return "" }
        var result = desc
        let tagRange = NSRange(result.startIndex..., in: result)
        result = tagStripRegex.stringByReplacingMatches(
            in: result, options: [], range: tagRange, withTemplate: " "
        )
        let wsRange = NSRange(result.startIndex..., in: result)
        result = whitespaceRegex.stringByReplacingMatches(
            in: result, options: [], range: wsRange, withTemplate: " "
        )
        return
            result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .htmlEntityDecoded
    }

    // MARK: - Cached regexes voor performance

    private static let tagStripRegex = try! NSRegularExpression(pattern: "<[^>]+>", options: [])
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+", options: [])

    private static let scriptRegex = try! NSRegularExpression(
        pattern: "(?i)<script[^>]*>[\\s\\S]*?</script>", options: []
    )
    private static let styleRegex = try! NSRegularExpression(
        pattern: "(?i)<style[^>]*>[\\s\\S]*?</style>", options: []
    )
    private static let noscriptRegex = try! NSRegularExpression(
        pattern: "(?i)<noscript[^>]*>[\\s\\S]*?</noscript>", options: []
    )
    private static let iframeRegex = try! NSRegularExpression(
        pattern: "(?i)<iframe[^>]*>[\\s\\S]*?</iframe>", options: []
    )

    var sanitisedHTML: String {
        guard let html = itemDescription, !html.isEmpty else { return "" }
        var result = html

        let regexes = [Self.scriptRegex, Self.styleRegex, Self.noscriptRegex, Self.iframeRegex]
        for regex in regexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result
    }

    var hasSubstantialContent: Bool {
        plainDescription.count > AppConfiguration.minimumContentLength
    }

    var fullText: String {
        "\(title) \(plainDescription)"
    }

    // MARK: - Video detectie

    var youtubeVideoID: String? {
        guard let link, link.contains("youtube.com") || link.contains("youtu.be") else { return nil }
        guard let url = URL(string: link) else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let v = components.queryItems?.first(where: { $0.name == "v" })?.value
        {
            return v
        }
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        return nil
    }

    var vimeoVideoID: String? {
        guard let link, link.contains("vimeo.com") else { return nil }
        guard let url = URL(string: link) else { return nil }
        return url.pathComponents.reversed().first { Int($0) != nil }
    }

    var directVideoURL: URL? {
        guard let mime = enclosureMIMEType, mime.hasPrefix("video/"),
            let urlStr = enclosureURL
        else { return nil }
        return URL(string: urlStr)
    }

    var isVideoItem: Bool {
        youtubeVideoID != nil || vimeoVideoID != nil || directVideoURL != nil
    }

    // MARK: - Audio detectie

    var directAudioURL: URL? {
        guard let mime = enclosureMIMEType, mime.hasPrefix("audio/"),
            let urlStr = enclosureURL
        else { return nil }
        return URL(string: urlStr)
    }

    var isAudioItem: Bool { directAudioURL != nil }

    var videoPlayerURL: URL? {
        if let id = youtubeVideoID { return URL(string: "https://youtu.be/\(id)") }
        if let id = vimeoVideoID { return URL(string: "https://vimeo.com/\(id)") }
        return nil
    }
}

// MARK: - HTML-entiteiten decoderen

extension String {
    // Gecachede regex — wordt eenmalig aangemaakt voor de gehele app-sessie
    private static let numericEntityRegex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")

    fileprivate var htmlEntityDecoded: String {
        guard self.contains("&") else { return self }
        var s = self
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&hellip;", "…"), ("&bull;", "•"), ("&copy;", "©"),
            ("&reg;", "®"), ("&trade;", "™"), ("&euro;", "€"),
        ]
        for (entity, char) in named {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        guard s.contains("&#"), let regex = Self.numericEntityRegex else { return s }
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: s),
                let numRange = Range(match.range(at: 2), in: s)
            else { continue }
            let isHex = match.range(at: 1).length > 0
            let numStr = String(s[numRange])
            if let code = isHex ? UInt32(numStr, radix: 16) : UInt32(numStr),
                let scalar = Unicode.Scalar(code)
            {
                s.replaceSubrange(range, with: String(scalar))
            }
        }
        return s
    }
}
