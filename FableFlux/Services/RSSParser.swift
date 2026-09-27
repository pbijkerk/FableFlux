import Foundation
import OSLog

struct ParsedFeedItem {
    var title: String = ""
    var link: String = ""
    var description: String = ""
    var pubDate: Date?
    var guid: String = ""
    var enclosureURL: String? = nil
    var enclosureMIMEType: String? = nil
    var imageURL: String? = nil
}

struct ParsedFeed {
    var title: String = ""
    var description: String = ""
    var items: [ParsedFeedItem] = []
    var detectedMediaType: FeedMediaType = .unknown
}

class RSSParser: NSObject, XMLParserDelegate {
    private var result = ParsedFeed()
    private var currentItem: ParsedFeedItem?
    private var currentText = ""
    private var currentElement = ""
    private var insideItem = false
    private var insideChannel = false
    private var channelTitleSet = false
    private var channelDescSet = false

    private let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.feed
    )

    // Gecachede regex — eenmalig aangemaakt voor de klasse
    private static let imgSrcRegex = try? NSRegularExpression(
        pattern: "<img[^>]+src=\"([^\"]+)\"",
        options: .caseInsensitive
    )

    func parse(data: Data) -> ParsedFeed {
        result = ParsedFeed()
        currentItem = nil
        currentText = ""
        currentElement = ""
        insideItem = false
        insideChannel = false
        channelTitleSet = false
        channelDescSet = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if result.items.contains(where: { $0.enclosureMIMEType?.hasPrefix("audio/") == true }) {
            result.detectedMediaType = .audio
        } else if result.items.contains(where: { $0.enclosureMIMEType?.hasPrefix("video/") == true }) {
            result.detectedMediaType = .video
        }

        return result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        currentText = ""

        switch currentElement {
        case "item", "entry":
            insideItem = true
            currentItem = ParsedFeedItem()
            if currentElement == "entry", let link = attributeDict["href"] {
                currentItem?.link = link
            }
        case "channel", "feed":
            insideChannel = true
        case "link":
            if insideItem, let href = attributeDict["href"], !href.isEmpty {
                currentItem?.link = href
            }
        case "enclosure":
            if insideItem {
                currentItem?.enclosureURL = attributeDict["url"]
                currentItem?.enclosureMIMEType = attributeDict["type"]
                if let type = attributeDict["type"], type.hasPrefix("image/"),
                    let url = attributeDict["url"]
                {
                    currentItem?.imageURL = url
                }
            }
        case "media:content", "media:thumbnail":
            if insideItem, currentItem?.imageURL == nil {
                if let url = attributeDict["url"],
                    attributeDict["medium"] == "image" || elementName.contains("thumbnail")
                {
                    currentItem?.imageURL = url
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if insideItem {
            switch element {
            case "title":
                currentItem?.title = text
            case "link":
                if let item = currentItem, item.link.isEmpty {
                    currentItem?.link = text
                }
            case "description", "summary", "content", "content:encoded":
                if let current = currentItem?.description, current.isEmpty || element == "content:encoded" {
                    currentItem?.description = text
                }
            case "pubdate", "published", "updated", "dc:date":
                // Alleen overschrijven bij een geslaagde parse: een <updated> dat niet te
                // lezen is mag een wél gelezen <published> niet wissen.
                if let date = parseDate(text) { currentItem?.pubDate = date }
            case "guid", "id":
                currentItem?.guid = text
            case "item", "entry":
                // `var`, niet `let`: ParsedFeedItem is een struct. Bij `let` werd de
                // gevonden afbeelding op `currentItem` gezet terwijl de al gemaakte kopie
                // werd toegevoegd, waardoor de terugval op de eerste <img> in de
                // beschrijving nooit in de feed terechtkwam.
                if var item = currentItem {
                    if item.imageURL == nil, !item.description.isEmpty {
                        item.imageURL = extractImageURL(from: item.description)
                    }
                    result.items.append(item)
                }
                currentItem = nil
                insideItem = false
            default:
                break
            }
        } else if insideChannel {
            switch element {
            case "title":
                if !channelTitleSet {
                    result.title = text
                    channelTitleSet = true
                }
            case "description", "subtitle":
                if !channelDescSet {
                    result.description = text
                    channelDescSet = true
                }
            default:
                break
            }
        }
    }

    // MARK: - Foutafhandeling

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        logger.error("XML parse error: \(parseError.localizedDescription)")
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        logger.warning("XML validation error: \(validationError.localizedDescription)")
    }

    // MARK: - Hulpfuncties

    /// Leest een publicatiedatum, en wantrouwt de uitkomst wanneer die ver in de toekomst
    /// ligt. `DateFormatter.date(from:)` matcht een *prefix*: een veld dat toevallig met
    /// iets datumachtigs begint levert dan een datum op die nooit is bedoeld. Zo'n datum
    /// blijft hangen — het artikel sorteert bovenaan, valt binnen elk samenvattingsvenster
    /// en wordt door de bewaarperiode nooit opgeruimd, dus het komt na elke verversing
    /// terug. Een mislukte parse is daarom beter dan een verzonnen datum: zonder datum valt
    /// het artikel terug op `fetchedAt` en gedraagt het zich gewoon (#89).
    private func parseDate(_ string: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSxxx",
            "yyyy-MM-dd",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            guard let date = formatter.date(from: string) else { continue }
            // Geen `return nil` hier: een volgend formaat kan dezelfde tekst wél
            // geloofwaardig lezen.
            if Self.isPlausiblePublicationDate(date) { return date }
            logger.warning("Onwaarschijnlijke publicatiedatum genegeerd: \(string, privacy: .public)")
        }
        return nil
    }

    /// Een publicatiedatum mag hooguit `maxFutureDateSkew` vóórlopen op de klok.
    /// Datums in het verleden blijven onaangeroerd: die corrigeren zichzelf — ze sorteren
    /// achteraan en vallen vanzelf buiten de bewaarperiode.
    static func isPlausiblePublicationDate(_ date: Date, now: Date = Date()) -> Bool {
        date <= now.addingTimeInterval(AppConfiguration.maxFutureDateSkew)
    }

    private func extractImageURL(from html: String) -> String? {
        guard let regex = Self.imgSrcRegex else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
            match.numberOfRanges > 1,
            let swiftRange = Range(match.range(at: 1), in: html)
        else { return nil }

        let imageURL = String(html[swiftRange])
        if imageURL.contains("1x1") || imageURL.contains("pixel") || imageURL.contains("tracker")
            || (imageURL.hasSuffix(".gif") && imageURL.count < 50)
        {
            return nil
        }
        return imageURL
    }
}
