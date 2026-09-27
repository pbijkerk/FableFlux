import SwiftUI
import WebKit
import AVKit
import SafariServices

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let item: FeedItem

    /// Of dit de pagina is die de gebruiker daadwerkelijk bekijkt. Een pagina-`TabView`
    /// houdt de buurpagina's in leven, en die zijn niet gratis: elke levende pagina zette
    /// zijn knoppen in dezelfde navigatiebalk (die stonden dan dubbel, #98) en startte
    /// artikel-extractie plus een fact-check — netwerkwerk tijdens de veeg, voor een
    /// pagina die je misschien nooit ziet (#106).
    ///
    /// `ArticlePageView` geeft alleen de zichtbare pagina `true` mee. Standaard `true`,
    /// zodat het scherm losstaand — vanuit de samenvatting — ongewijzigd werkt.
    var isActive = true

    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize) private var articleFontSize = AppConfiguration
        .defaultArticleFontSize
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontFamily) private var articleFontFamily = AppConfiguration
        .defaultArticleFontFamily
    @AppStorage(AppConfiguration.UserDefaultsKeys.showBiasIndicators) private var showBiasIndicators = true

    @State private var displayHTML: String = ""
    @State private var isExtracting = false
    @State private var extractionFailed = false
    @State private var showingVideoPlayer = false
    @State private var safariItem: IdentifiableURL? = nil
    @State private var readingProgress: Double = 0
    @State private var opslagFout: OpslagFoutmelding?
    @StateObject private var extractor = ArticleExtractorService()

    private var articleURL: URL? {
        guard let link = item.link else { return nil }
        return URL(string: link)
    }

    /// Accentkleur van de bron — bepaalt de leesvoortgangsbalk.
    private var brand: Color {
        Theme.brandColor(for: item.feed?.title ?? item.feed?.url ?? "")
    }

    private var canExtract: Bool {
        !item.isVideoItem && !item.isAudioItem
            && item.feed?.isMastodonFeed != true
            && articleURL != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceRatingStrip
            Group {
                if item.isAudioItem {
                    audioLayout
                } else if item.isVideoItem {
                    videoLayout
                } else {
                    readerLayout
                }
            }
        }
        // Ook het artikel zelf: tot de webview zijn eerste frame tekent, toont een
        // achtergrondloze VStack de systeemstandaard in plaats van de appkleur.
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { readingProgressBar }
        .navigationTitle(item.feed?.title ?? "Artikel")
        .navigationBarTitleDisplayMode(.inline)
        // Geen eigen .toolbarBackground: op iOS 26 is de balk een zwevende capsule die
        // zelf een scroll-edge-effect over de inhoud legt. Een afgedwongen materiaal
        // verdringt dat effect, waardoor tekst er scherp doorheen komt (#63).
        .toolbar { toolbarContent }
        .sheet(item: $safariItem) { item in
            SafariVideoPlayer(url: item.url).ignoresSafeArea()
        }
        .opslagFoutmelding($opslagFout)
        // `task(id:)` en niet `task`: het werk start zodra deze pagina de zichtbare wordt,
        // en wordt afgebroken zodra je doorveegt. Een `.task` zonder id zou bij een
        // buurpagina één keer draaien en daarna nooit meer, ook niet als je er belandt.
        .task(id: isActive) {
            guard isActive else { return }
            async let content: Void = loadContent()
            async let factCheck: Void = FactCheckService.shared.checkItem(item, context: modelContext)
            _ = await (content, factCheck)
        }
        // Gelezen is wat je bekeken hebt, niet wat naast je scherm klaarstond.
        .onChange(of: isActive, initial: true) { _, active in
            guard active, !item.isRead else { return }
            item.isRead = true
            modelContext.saveOrLog("de gelezen-markering te bewaren")
        }
    }

    // MARK: - Audio layout

    @ViewBuilder
    private var audioLayout: some View {
        if let audioURL = item.directAudioURL {
            VStack(spacing: 0) {
                // Vrij van de zwevende iOS 26-balk: de speler staat bovenaan en werd
                // er anders door afgesneden (#63).
                AudioPlayerView(url: audioURL)
                    .padding(.top, CGFloat(AppConfiguration.floatingNavBarClearance))
                ReaderWebView(
                    html: displayHTML,
                    baseURL: articleURL,
                    onLoadFullArticle: articleURL != nil ? { Task { await extractFromWeb() } } : nil,
                    onOpenURL: openInAppBrowser,
                    onScrollProgress: { readingProgress = $0 }
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Video layout

    @ViewBuilder
    private var videoLayout: some View {
        if let videoURL = item.directVideoURL {
            nativePlayerLayout(videoURL: videoURL)
        } else if let playerURL = item.videoPlayerURL {
            safariPlayerLayout(playerURL: playerURL)
        }
    }

    private func safariPlayerLayout(playerURL: URL) -> some View {
        VStack(spacing: 0) {
            VideoPlayButton(isPresented: $showingVideoPlayer, playerURL: playerURL)
                .padding(.top, CGFloat(AppConfiguration.floatingNavBarClearance))
            ReaderWebView(html: descriptionHTML, baseURL: articleURL, onOpenURL: openInAppBrowser)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func nativePlayerLayout(videoURL: URL) -> some View {
        VStack(spacing: 0) {
            NativeVideoPlayer(url: videoURL)
                .frame(height: UIScreen.main.bounds.width * 9 / 16)
                .padding(.top, CGFloat(AppConfiguration.floatingNavBarClearance))
            if !displayHTML.isEmpty {
                ReaderWebView(html: displayHTML, baseURL: articleURL, onOpenURL: openInAppBrowser)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Reader layout

    private var readerLayout: some View {
        ZStack {
            ReaderWebView(
                html: displayHTML,
                baseURL: articleURL,
                onLoadFullArticle: articleURL != nil ? { Task { await extractFromWeb() } } : nil,
                onOpenURL: openInAppBrowser,
                onScrollProgress: { readingProgress = $0 }
            )
            .ignoresSafeArea(edges: .bottom)

            if isExtracting {
                LoadingOverlay(message: "Artikel laden…")
            }
        }
    }

    /// Compacte bron-duidingsstrip boven alle layouts (audio/video/reader).
    /// Toont politieke positie (BiasBarView) en betrouwbaarheid (ReliabilityBadgeView)
    /// alleen wanneer de feed een beoordeling heeft. Tik op de balk opent de
    /// bestaande transparantie-sheet ("Over deze bron"). Consistent met FeedItemsView.
    @ViewBuilder
    private var sourceRatingStrip: some View {
        if showBiasIndicators, let feed = item.feed, let score = feed.biasScore {
            HStack(alignment: .center, spacing: 8) {
                BiasBarView(
                    biasScore: score,
                    feedName: feed.title,
                    reliabilityLevel: feed.reliabilityLevel,
                    ratingSource: feed.ratingSource,
                    biasRatedAt: feed.biasRatedAt
                )
                ReliabilityBadgeView(level: feed.reliabilityLevel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.card)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    /// Flinterdunne leesvoortgangsbalk bovenin, in de accentkleur van de bron.
    @ViewBuilder
    private var readingProgressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(brand)
                .frame(width: geo.size.width * readingProgress, height: 3)
                .animation(.linear(duration: 0.1), value: readingProgress)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }

    private func openInAppBrowser(_ url: URL) {
        safariItem = IdentifiableURL(url: url)
    }

    /// De URL hoort alleen te gelden voor de knoppen die hem nodig hebben. Eerder stond de
    /// hele groep achter `let url = articleURL`, waardoor een artikel zonder link — een
    /// Mastodon-bericht zonder externe verwijzing — helemaal geen knoppen kreeg, ook geen
    /// bewaarknop (#118). Juist zo'n bericht wil je kunnen bewaren.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isActive {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if extractionFailed, articleURL != nil {
                    Button {
                        Task { await extractFromWeb() }
                    } label: {
                        Label("Opnieuw laden", systemImage: "arrow.clockwise")
                    }
                    .disabled(isExtracting)
                }

                Button {
                    item.isSaved.toggle()
                    modelContext.saveOrReport("de bewaarstatus van het artikel te wijzigen", melding: &opslagFout)
                } label: {
                    Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(item.isSaved ? "Verwijder uit bewaard" : "Bewaar artikel")

                if let url = articleURL {
                    Button {
                        safariItem = IdentifiableURL(url: url)
                    } label: {
                        Label("Open in browser", systemImage: "safari")
                    }

                    ShareLink(item: url) {
                        Label("Delen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - HTML helpers

    private var descriptionHTML: String {
        ArticleHTMLBuilder.build(
            content: item.sanitisedHTML.isEmpty
                ? "<p><em>Geen beschrijving beschikbaar.</em></p>"
                : item.sanitisedHTML,
            title: item.title,
            feedName: item.feed?.title,
            date: item.pubDate,
            fontSize: articleFontSize,
            fontFamily: articleFontFamily,
            topPadding: htmlTopPadding
        )
    }

    /// De webview staat alleen bij de reader-layout bovenaan; bij audio en video zit er
    /// een speler boven die de balk al vrijhoudt.
    private var htmlTopPadding: Int {
        (item.isAudioItem || item.isVideoItem) ? 16 : AppConfiguration.floatingNavBarClearance
    }

    // MARK: - Content laden

    private func escapeHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func loadContent() async {
        guard !item.isVideoItem else { return }
        let articleLink = item.feed?.isMastodonFeed == true ? nil : item.link
        var rssHTML = item.sanitisedHTML
        // Artikelen die vóór de escaping-fix zijn opgeslagen bevatten de onbewerkte URL;
        // daarom telt zowel de ge-escapete als de onbewerkte vorm als "staat er al in".
        if item.feed?.isMastodonFeed == true,
            let imgURL = item.enclosureURL,
            !rssHTML.contains(escapeHTML(imgURL)),
            !rssHTML.contains(imgURL)
        {
            rssHTML +=
                "\n<img src=\"\(escapeHTML(imgURL))\" alt=\"\" style=\"max-width:100%;border-radius:8px;margin:8px 0;display:block;\">"
        }
        if !rssHTML.isEmpty {
            displayHTML = ArticleHTMLBuilder.build(
                content: rssHTML,
                title: item.title,
                feedName: item.feed?.title,
                date: item.pubDate,
                articleLink: articleLink,
                fontSize: articleFontSize,
                fontFamily: articleFontFamily,
                topPadding: htmlTopPadding
            )
        } else {
            displayHTML = ArticleHTMLBuilder.build(
                content:
                    "<p><em>Geen samenvatting beschikbaar. Tik op de titel om het volledige artikel te lezen.</em></p>",
                title: item.title,
                feedName: item.feed?.title,
                date: item.pubDate,
                articleLink: articleLink,
                fontSize: articleFontSize,
                fontFamily: articleFontFamily,
                topPadding: htmlTopPadding
            )
        }
    }

    private func extractFromWeb(url: URL? = nil) async {
        guard let url = url ?? articleURL else { return }
        isExtracting = true
        extractionFailed = false
        do {
            let html = try await extractor.extract(from: url)
            displayHTML = ArticleHTMLBuilder.build(
                content: html.isEmpty ? "<p><em>Geen inhoud gevonden.</em></p>" : html,
                title: item.title,
                feedName: item.feed?.title,
                date: item.pubDate,
                fontSize: articleFontSize,
                fontFamily: articleFontFamily,
                topPadding: htmlTopPadding
            )
        } catch {
            extractionFailed = true
        }
        isExtracting = false
    }
}

// MARK: - ArticleHTMLBuilder

/// Bouwt het volledige HTML-document voor de reader-weergave.
/// Geïsoleerd van de view zodat dit los getest en hergebruikt kan worden.
enum ArticleHTMLBuilder {

    static func build(
        content: String,
        title: String,
        feedName: String?,
        date: Date?,
        articleLink: String? = nil,
        fontSize: Int = AppConfiguration.defaultArticleFontSize,
        fontFamily: String = AppConfiguration.defaultArticleFontFamily,
        topPadding: Int = AppConfiguration.floatingNavBarClearance
    ) -> String {
        let dateStr: String
        if let date {
            let fmt = DateFormatter()
            fmt.dateStyle = .long
            fmt.timeStyle = .none
            fmt.locale = Locale.current
            dateStr = fmt.string(from: date)
        } else {
            dateStr = ""
        }

        let meta = [feedName, dateStr].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        let bodyFont: String
        switch fontFamily {
        case "charter": bodyFont = "Charter, Georgia, 'Times New Roman', serif"
        case "newyork": bodyFont = "'New York', Georgia, serif"
        case "georgia": bodyFont = "Georgia, 'Times New Roman', serif"
        default: bodyFont = "-apple-system, 'SF Pro Text', sans-serif"
        }

        // Categorie-/bron-label boven de titel in de accentkleur van de bron
        let categoryHTML =
            (feedName?.isEmpty == false)
            ? "<p class=\"category-label\">\(escape(feedName!.uppercased()))</p>"
            : ""

        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
            <style>
            /* Retro Future — warme tinten, tijdschrift-leesomgeving */
            :root {
                --text:      #1C1C1E;
                --bg:        #F4F3EF;   /* Cream Sand */
                --card:      #FDFDFB;   /* Alabaster */
                --secondary: #6E6A62;
                --accent:    #FF9500;   /* Rich Amber */
                --link:      #C0631F;
                --code-bg:   rgba(0,0,0,0.05);
                --border:    rgba(0,0,0,0.10);
            }
            @media (prefers-color-scheme: dark) {
                :root {
                    --text:      #F2F2F7;
                    --bg:        #121214;   /* Velvet Night */
                    --card:      #1E1E22;   /* Onyx */
                    --secondary: #A8A29A;
                    --accent:    #FFB340;   /* Neon Amber */
                    --link:      #FFB340;
                    --code-bg:   rgba(255,255,255,0.07);
                    --border:    rgba(255,255,255,0.12);
                }
            }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html { background: var(--bg); }
            body {
                font-family: \(bodyFont);
                font-size: \(fontSize)px;
                line-height: 1.72;
                color: var(--text);
                background: var(--bg);
                /* Bovenmarge komt van buiten: bij de reader-layout staat de webview
                   bovenaan en moet de tekst vrij van de zwevende balk beginnen; bij audio
                   en video staat er een speler boven en is die ruimte niet nodig (#63). */
                padding: \(topPadding)px 24px 64px;
                max-width: 680px;
                margin: 0 auto;
                word-break: break-word;
                -webkit-text-size-adjust: 100%;
            }
            .category-label { font-family: -apple-system, sans-serif; font-size: 0.72em; font-weight: 800; letter-spacing: 0.12em; color: var(--accent); margin-bottom: 0.5em; }
            .article-title { font-family: Charter, Georgia, serif; font-size: 1.7em; font-weight: 900; line-height: 1.18; margin-bottom: 0.35em; letter-spacing: -0.01em; }
            .article-meta { font-size: 0.8em; color: var(--secondary); margin-bottom: 1.8em; padding-bottom: 1.2em; border-bottom: 1px solid var(--border); }
            h1, h2, h3, h4, h5, h6 { font-family: Charter, Georgia, serif; font-weight: 800; line-height: 1.3; margin: 1.5em 0 0.45em; }
            h1 { font-size: 1.4em; } h2 { font-size: 1.2em; } h3 { font-size: 1.05em; }
            p { margin: 0.95em 0; }
            a { color: var(--link); text-decoration: none; border-bottom: 1px solid color-mix(in srgb, var(--link) 35%, transparent); }
            a:active { opacity: 0.6; }
            img, video { max-width: 100%; height: auto; border-radius: 14px; margin: 0.8em 0; display: block; }
            figure { margin: 1.2em 0; }
            figcaption, .wp-caption-text, .caption { font-size: 0.8em; color: var(--secondary); text-align: center; margin-top: 0.4em; }
            blockquote { border-left: 3px solid var(--accent); padding: 0.3em 0 0.3em 1.1em; color: var(--secondary); margin: 1.2em 0; font-style: italic; }
            pre { background: var(--code-bg); padding: 14px; border-radius: 12px; overflow-x: auto; font-size: 0.85em; line-height: 1.5; margin: 1em 0; }
            code { font-family: 'SF Mono', Menlo, monospace; font-size: 0.875em; background: var(--code-bg); padding: 2px 5px; border-radius: 4px; }
            pre code { background: none; padding: 0; border-radius: 0; }
            ul, ol { padding-left: 1.4em; margin: 0.9em 0; }
            li { margin: 0.35em 0; }
            table { width: 100%; border-collapse: collapse; font-size: 0.9em; margin: 1em 0; overflow-x: auto; display: block; }
            th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
            th { background: var(--code-bg); font-weight: 600; }
            hr { border: none; border-top: 1px solid var(--border); margin: 1.6em 0; }
            .article-title-link { text-decoration: none; color: inherit; display: block; }
            .article-title-link:active .article-title { opacity: 0.6; }
            .read-full-hint { font-family: -apple-system, sans-serif; font-size: 13px; font-weight: 600; color: var(--accent); margin-top: 2px; margin-bottom: 18px; border: none; }
            </style>
            </head>
            <body>
            \(articleLink != nil ? "<a href=\"rssreader://load-full-article\" class=\"article-title-link\">" : "")
            \(categoryHTML)
            <h1 class="article-title">\(escape(title))</h1>
            \(articleLink != nil ? "<p class=\"read-full-hint\">Tik voor het volledige artikel ›</p></a>" : "")
            \(meta.isEmpty ? "" : "<p class=\"article-meta\">\(escape(dateStr))</p>")
            \(content)
            </body>
            </html>
            """
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Hulp-views

private struct VideoPlayButton: View {
    @Binding var isPresented: Bool
    let playerURL: URL

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(16 / 9, contentMode: .fit)
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                    Text("Tik om af te spelen")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isPresented) {
            SafariVideoPlayer(url: playerURL).ignoresSafeArea()
        }
    }
}

private struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - SafariVideoPlayer

struct SafariVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    var onLoadFullArticle: (() -> Void)? = nil
    var onOpenURL: ((URL) -> Void)? = nil
    var onScrollProgress: ((Double) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.scrollView.delegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Ondoorzichtig, met dezelfde kleur als de HTML-achtergrond (Theme.background en
        // --bg delen hun waarden). Een doorzichtige webview geeft het scroll-edge-effect
        // niets om overheen te vervagen; de tekst kwam er dan recht doorheen (#63).
        wv.isOpaque = true
        wv.backgroundColor = UIColor(Theme.background)
        wv.scrollView.backgroundColor = UIColor(Theme.background)
        // Een webview zonder geladen document tekent zichzelf wit: met `isOpaque = true`
        // schildert WebKit, en de `backgroundColor` hierboven komt er niet doorheen. Sinds
        // #107 laadt een buurpagina zijn HTML pas wanneer hij de zichtbare wordt, dus was
        // die witte vlek tijdens het vegen zichtbaar — in beide kleurmodi, want het is
        // WebKits wit en niet dat van de app. Een leeg document met dezelfde achtergrond
        // dekt de periode tot de echte HTML er is.
        wv.loadHTMLString(Self.leegDocument, baseURL: nil)
        return wv
    }

    /// Dezelfde waarden als `--bg` in `ArticleHTMLBuilder` en `Theme.background`.
    private static let leegDocument = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; height: 100%; background: #F4F3EF; }
          @media (prefers-color-scheme: dark) { html, body { background: #121214; } }
        </style>
        </head><body></body></html>
        """

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        context.coordinator.initialLoadDone = false
        wv.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadFullArticle: onLoadFullArticle,
            onOpenURL: onOpenURL,
            onScrollProgress: onScrollProgress)
    }

    class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var lastHTML: String = ""
        var initialLoadDone = false
        let onLoadFullArticle: (() -> Void)?
        let onOpenURL: ((URL) -> Void)?
        let onScrollProgress: ((Double) -> Void)?

        init(
            onLoadFullArticle: (() -> Void)?,
            onOpenURL: ((URL) -> Void)?,
            onScrollProgress: ((Double) -> Void)? = nil
        ) {
            self.onLoadFullArticle = onLoadFullArticle
            self.onOpenURL = onOpenURL
            self.onScrollProgress = onScrollProgress
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let onScrollProgress else { return }
            let scrollable = scrollView.contentSize.height - scrollView.bounds.height
            guard scrollable > 1 else {
                onScrollProgress(0)
                return
            }
            let raw = scrollView.contentOffset.y / scrollable
            onScrollProgress(min(max(raw, 0), 1))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            initialLoadDone = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            initialLoadDone = true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "rssreader" {
                onLoadFullArticle?()
                decisionHandler(.cancel)
            } else if (url.scheme == "https" || url.scheme == "http") && initialLoadDone {
                if let onOpenURL {
                    onOpenURL(url)
                } else {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
