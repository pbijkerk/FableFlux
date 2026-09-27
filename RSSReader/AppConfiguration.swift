import Foundation

/// Centrale configuratie voor de hele app — voorkomt magic numbers en duplicatie.
enum AppConfiguration {

    // MARK: - Content thresholds

    /// Minimum aantal tekens voor "substantial content" in reader mode
    static let minimumContentLength = 200

    /// Maximum aantal feeds dat parallel ververst kan worden
    static let maxParallelRefreshes = 10

    /// Ruimte die het eerste element vrij moet houden van de zwevende iOS 26-navigatiebalk.
    /// Die balk zweeft over de inhoud, dus wat bovenaan begint verdwijnt er anders achter.
    static let floatingNavBarClearance = 72

    /// Minimale tijd tussen twee automatische clusteringrondes. Geldt niet wanneer de
    /// gebruiker zelf om een refresh vraagt (pull-to-refresh).
    static let clusteringDebounce: TimeInterval = 120

    /// Hoe ver de samenvatting op Vandaag terugkijkt. 48 uur houdt "gisteren en vandaag"
    /// binnen bereik — een dag overslaan kost geen nieuws — terwijl artikelen uit de rest
    /// van de bewaarperiode buiten de samenvatting blijven (#89).
    static let summaryWindow: TimeInterval = 48 * 3600

    /// Hoeveel artikelen de lijst in één keer ophaalt, en met hoeveel hij groeit zodra je
    /// het einde nadert. Zonder begrenzing komt de hele bewaarperiode in één fetch van
    /// schijf — de meting bij #106 liet zien dat dat de main thread seconden laat wachten
    /// op I/O. Vijftig is ruim een schermvulling, zodat je de grens zelden voelt.
    static let articlePageSize = 50

    /// Hoeveel een publicatiedatum vóór mag lopen op de klok voordat hij ongeloofwaardig is.
    /// Een uitgever met een afwijkende klok of een tijdzone die net verkeerd wordt opgegeven
    /// scheelt hooguit uren; een datum die verder in de toekomst ligt komt uit een verkeerd
    /// gelezen veld, niet uit de werkelijkheid.
    static let maxFutureDateSkew: TimeInterval = 24 * 3600

    // MARK: - Retention

    /// Standaard aantal dagen dat artikelen bewaard blijven (als feed geen eigen instelling heeft)
    static let defaultRetentionDays = 30

    // MARK: - API & Network

    /// Timeout voor artikel-extractie (in seconden)
    static let articleExtractionTimeout: TimeInterval = 30

    /// Timeout voor netwerk-requests (in seconden)
    static let networkTimeout: TimeInterval = 30

    /// Maximum aantal artikelen per Claude summary request
    static let maxArticlesPerSummary = 10

    /// Maximum aantal tokens voor Claude responses
    static let claudeMaxTokens = 600

    // MARK: - UI

    /// Standaard fontsize voor artikel-weergave
    static let defaultArticleFontSize = 17

    /// Standaard lettertypefamilie voor artikel-weergave
    static let defaultArticleFontFamily = "charter"

    /// Standaard schaalfactor voor de Feeds-lijst (tekst + iconen)
    static let defaultFeedListScale: Double = 1.0

    /// Standaard tekstgrootte voor bronanalyse (bias-balk, betrouwbaarheid, fact-check)
    static let defaultAnalysisTextSize = 12

    /// Maximale breedte van een bron-chip in de samenvatting (begrenst lange titels)
    static let summarySourceChipMaxWidth: CGFloat = 220

    /// Aantal beweringen dat een Vandaag-kaart standaard toont vóór "Toon meer"
    static let summaryCardCollapsedStatementCount = 3

    // MARK: - Clustering

    /// Minimum aantal trefwoord-treffers (op woordgrens) voordat een artikel aan
    /// zijn best scorende onderwerp wordt toegewezen. Onder deze drempel volgt
    /// geen toewijzing. Standaard 1: dankzij de woordgrens-matching valt de ruis
    /// van deelstring-treffers (bijv. "ai" in "email") al weg, dus is één echte
    /// hele-woord-treffer een betekenisvol signaal en behoudt recall. Verhoog naar
    /// 2 om toevalsruis strenger te weren ten koste van dekking.
    static let minimumClusterScore = 1

    /// Om de hoeveel artikelen de clustering-lus op annulering controleert. De check
    /// is goedkoop maar niet gratis; per artikel controleren levert bij duizenden
    /// artikelen onnodige overhead, terwijl deze stap ruim binnen één frame blijft.
    static let clusteringCancellationCheckInterval = 64

    // MARK: - UserDefaults Keys

    enum UserDefaultsKeys {
        static let retentionDays = "defaultRetentionDays"
        static let claudeAPIKey = "claudeAPIKey"  // legacy – gebruik Keychain
        static let articleFontSize = "articleFontSize"
        static let articleFontFamily = "articleFontFamily"
        static let hideReadArticles = "hideReadArticles"
        static let feedCountMode = "feedCountMode"
        static let previewLineCount = "previewLineCount"
        static let showArticleThumbnails = "showArticleThumbnails"
        static let summaryLanguage = "summaryLanguage"
        static let feedListScale = "feedListScale"
        static let summaryLength = "summaryLength"
        static let showBiasIndicators = "showBiasIndicators"
        static let analysisTextSize = "analysisTextSize"
        /// UUID-string van de actieve mapfilter op de artikelstroom; leeg = alle mappen.
        static let articlesFolderFilter = "articlesFolderFilter"
        /// Gekozen `AppTheme` (rawValue): bepaalt app-icoon en accentkleur.
        static let appTheme = "appTheme"
    }

    // MARK: - Summary length

    enum SummaryLength: String, CaseIterable {
        case kort = "kort"
        case normaal = "normaal"
        case uitgebreid = "uitgebreid"

        var label: String {
            switch self {
            case .kort: return "Kort (2–3 zinnen)"
            case .normaal: return "Normaal (4–6 zinnen)"
            case .uitgebreid: return "Uitgebreid (8–10 zinnen)"
            }
        }

        var sentenceInstruction: (nl: String, en: String) {
            switch self {
            case .kort:
                return (
                    "Schrijf een samenvatting van 2 tot 3 zinnen in het Nederlands die de kern beschrijft. Wees feitelijk en objectief.",
                    "Write a summary of 2 to 3 sentences in English describing the core theme. Be factual and objective."
                )
            case .normaal:
                return (
                    "Schrijf een samenvatting van 4 tot 6 zinnen in het Nederlands die de belangrijkste thema's en ontwikkelingen beschrijft. Wees feitelijk en objectief.",
                    "Write a summary of 4 to 6 sentences in English describing the main themes and developments. Be factual and objective."
                )
            case .uitgebreid:
                return (
                    "Schrijf een samenvatting van 8 tot 10 zinnen in het Nederlands die de belangrijkste thema's, ontwikkelingen en achtergronden uitgebreid beschrijft. Wees feitelijk en objectief.",
                    "Write a summary of 8 to 10 sentences in English describing the main themes, developments and context in detail. Be factual and objective."
                )
            }
        }

        var maxTokens: Int {
            switch self {
            case .kort: return 300
            case .normaal: return 600
            case .uitgebreid: return 1000
            }
        }

        var localSnippetCount: Int {
            switch self {
            case .kort: return 2
            case .normaal: return 5
            case .uitgebreid: return 8
            }
        }
    }

    static let defaultSummaryLength = SummaryLength.normaal.rawValue

    // MARK: - Keychain Keys

    /// Aantal dagen dat een fact-check resultaat geldig blijft vóór hercontrole
    static let factCheckCacheDays: Double = 7

    enum KeychainKeys {
        static let claudeAPIKey = "claudeAPIKey"
        static let googleFactCheckAPIKey = "googleFactCheckAPIKey"
        static func mastodonToken(instanceURL: String, accountID: String) -> String {
            "mastodon.token.\(instanceURL).\(accountID)"
        }
    }

    // MARK: - Logging

    enum LogSubsystem {
        static let main = "com.rssreader.app"

        enum Category {
            static let networking = "networking"
            static let clustering = "clustering"
            static let mastodon = "mastodon"
            static let feed = "feed"
            static let extraction = "extraction"
            static let persistence = "persistence"
        }
    }
}
