import Foundation

struct OPMLFeed {
    var title: String
    var xmlURL: String
    var htmlURL: String?
    var type: String?
    var folderName: String?  // populated when feed is inside a folder outline
}

class OPMLParser: NSObject, XMLParserDelegate {
    private var feeds: [OPMLFeed] = []

    /// Namen van de mapelementen die op dit moment openstaan, buitenste eerst.
    private var openFolders: [String] = []

    /// Per openstaand `<outline>` of het een mapelement was. `didEndElement` kan dat zelf
    /// niet zien — het krijgt alleen de elementnaam — dus onthouden we het bij de starttag.
    /// Zonder die stapel verlaagt de sluitingstag van een feed de mapteller, waardoor elke
    /// feed ná de eerste zijn map kwijtraakt (#66, #78).
    private var outlineIsFolder: [Bool] = []

    func parse(data: Data) -> [OPMLFeed] {
        feeds = []
        openFolders = []
        outlineIsFolder = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return feeds
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let xmlURL = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"] ?? attributeDict["XMLURL"] ?? ""
        let title = attributeDict["title"] ?? attributeDict["text"] ?? attributeDict["Title"] ?? ""

        if !xmlURL.isEmpty {
            // This is a feed outline
            let feed = OPMLFeed(
                title: title.isEmpty ? "Unknown Feed" : title,
                xmlURL: xmlURL,
                htmlURL: attributeDict["htmlUrl"] ?? attributeDict["htmlurl"],
                type: attributeDict["type"],
                folderName: openFolders.first  // bij nesting wint de buitenste map
            )
            feeds.append(feed)
            outlineIsFolder.append(false)
        } else if !title.isEmpty {
            // Geen xmlUrl -> mapelement
            openFolders.append(title)
            outlineIsFolder.append(true)
        } else {
            // Outline zonder xmlUrl en zonder titel: telt niet mee, maar moet wel op de
            // stapel zodat de sluitingstag bij het juiste element hoort.
            outlineIsFolder.append(false)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }
        guard let wasFolder = outlineIsFolder.popLast() else { return }
        if wasFolder, !openFolders.isEmpty {
            openFolders.removeLast()
        }
    }
}
