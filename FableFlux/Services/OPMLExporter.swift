import Foundation
import UniformTypeIdentifiers

/// Bouwt een geldig OPML-bestand uit de huidige feeds, voor backup/herstel (#217).
/// Virtuele Mastodon-feeds (`mastodon://...`) worden overgeslagen: OPML is voor echte
/// RSS-URL's; een Mastodon-koppeling wordt na herstel apart opnieuw gelegd (besluit Peter,
/// 2026-11-01). Mapindeling blijft behouden, in dezelfde vorm die `OPMLParser` begrijpt —
/// een export is dus weer in FableFlux zelf te importeren met dezelfde mappen.
enum OPMLExporter {

    static func export(feeds: [Feed], folders: [FeedFolder]) -> String {
        var body = ""

        for folder in folders.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let folderFeeds = exportable(feeds, in: folder)
            guard !folderFeeds.isEmpty else { continue }
            body += "    <outline text=\"\(escape(folder.name))\">\n"
            for feed in folderFeeds {
                body += outlineLine(for: feed, indent: "      ")
            }
            body += "    </outline>\n"
        }

        for feed in exportable(feeds, in: nil) {
            body += outlineLine(for: feed, indent: "    ")
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>FableFlux-feeds</title>
              </head>
              <body>
            \(body)  </body>
            </opml>
            """
    }

    /// Feeds in `folder` (of zonder folder bij `nil`), zonder virtuele Mastodon-feeds,
    /// alfabetisch — dezelfde volgorde als `FeedListView` ze toont.
    private static func exportable(_ feeds: [Feed], in folder: FeedFolder?) -> [Feed] {
        feeds
            .filter { $0.folder?.id == folder?.id && !$0.isMastodonFeed }
            .sorted { $0.title < $1.title }
    }

    private static func outlineLine(for feed: Feed, indent: String) -> String {
        let title = escape(feed.title)
        let url = escape(feed.url)
        return "\(indent)<outline text=\"\(title)\" title=\"\(title)\" type=\"rss\" xmlUrl=\"\(url)\"/>\n"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// `Transferable`-wrapper voor `ShareLink`: het OPML-bestand wordt pas bij het delen zelf
/// opgebouwd (geen bestand op schijf vóór die tijd), met `.opml`-bestandsnaam voor Mail,
/// Bestanden, AirDrop, etc.
struct OPMLDocument: Transferable {
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .xml) { document in
            Data(document.content.utf8)
        }
        .suggestedFileName("fableflux-feeds.opml")
    }
}
