import SwiftData
import SwiftUI

/// Hoe de artikellijsten artikelen tonen (#225).
enum ArticleListStyle: String, CaseIterable, Identifiable {
    /// Beeldkaart met de kop over de afbeelding; tekstkaart als er geen afbeelding is.
    case imageFirst
    /// De bestaande kaart (`FeedItemCard`).
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .imageFirst: return "Beeld eerst"
        case .compact: return "Compact"
        }
    }
}

/// Eén artikel in een lijst, in de gekozen weergave. `isOlder` = onder de lijn "Hier was
/// je gebleven": lichter weergegeven.
struct ArticleCard: View {
    let item: FeedItem
    var isOlder = false
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleListStyle)
    private var style = ArticleListStyle.imageFirst.rawValue

    var body: some View {
        Group {
            if ArticleListStyle(rawValue: style) == .compact {
                FeedItemCard(item: item)
            } else {
                ImageFirstCard(item: item)
            }
        }
        .opacity(isOlder ? 0.6 : 1)
    }
}

// MARK: - Beeld eerst

/// Kaart "Beeld eerst" (#225, schets 2D). Met afbeelding: de kop over het beeld, met een
/// donker verloop eronder voor contrast. Zonder afbeelding: een tekstkaart met bron, kop en
/// twee regels inleiding, zonder placeholder of stockbeeld.
struct ImageFirstCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: FeedItem

    @AppStorage(AppConfiguration.UserDefaultsKeys.showArticleThumbnails) private var showImages = true
    @AppStorage(AppConfiguration.UserDefaultsKeys.showBiasIndicators) private var showBiasIndicators = true
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize) private var articleFontSize = AppConfiguration
        .defaultArticleFontSize
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 17

    @State private var image: UIImage?
    /// Afbeelding geladen maar onbruikbaar (te klein, fout, of offline zonder cache).
    @State private var imageFailed = false

    static let imageHeight: CGFloat = 230
    private static let shape = RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)

    private var titleSize: CGFloat { scaledBase * CGFloat(articleFontSize) / 17 + 1 }
    private var brand: Color { Theme.brandColor(for: item.feed?.title ?? item.feed?.url ?? "") }

    private var localImage: UIImage? { item.savedImageData.flatMap { UIImage(data: $0) } }
    private var imageURL: URL? { item.imageURL.flatMap { URL(string: $0) } }

    /// Of deze kaart (nog) een beeldkaart is: er is een afbeelding of er komt er een.
    private var showsImageCard: Bool {
        guard showImages, !imageFailed else { return false }
        return localImage != nil || image != nil || imageURL != nil
    }

    var body: some View {
        Group {
            if showsImageCard {
                imageCard
            } else {
                textCard
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        // Lui: pas als de kaart in beeld komt. Opnieuw zodra er een URL bij komt (og:image).
        .task(id: item.imageURL) { await loadImage() }
    }

    // MARK: Beeldkaart

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageArea
            if hasAnalysis {
                analysisRow.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .clipShape(Self.shape)
        .background { Self.shape.fill(Theme.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3) }
    }

    private var imageArea: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.imageHeight)
                .overlay {
                    if let shown = localImage ?? image {
                        Image(uiImage: shown)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        brand.opacity(0.15)
                    }
                }
                .clipped()

            // Verloop van transparant naar 85% zwart: witte tekst blijft op elke foto, in
            // licht en donker, ruim boven 4,5:1 (wit op ≥ 80% zwart ≈ 12:1).
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.imageHeight * 0.7)

            VStack(alignment: .leading, spacing: 6) {
                metaRow(color: .white.opacity(0.92))
                Text(item.title)
                    .font(Theme.title(titleSize, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) { statusBadge.padding(12) }
    }

    // MARK: Tekstkaart

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                metaRow(color: brand)
                Spacer(minLength: 0)
                statusBadge
            }
            Text(item.title)
                .font(Theme.title(titleSize, relativeTo: .headline))
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !item.plainDescription.isEmpty {
                Text(item.plainDescription)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            if hasAnalysis { analysisRow.padding(.top, 2) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { Self.shape.fill(Theme.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3) }
    }

    // MARK: Onderdelen

    private var hasAnalysis: Bool {
        showBiasIndicators && (item.feed?.biasScore != nil || !item.factCheckResults.isEmpty)
    }

    /// Bronduiding en fact-check, zoals op de compacte kaart: die horen bij FableFlux.
    @ViewBuilder
    private var analysisRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let feed = item.feed, let score = feed.biasScore {
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
            }
            if !item.factCheckResults.isEmpty {
                FactCheckChipView(results: item.factCheckResults)
            }
        }
    }

    private func metaRow(color: Color) -> some View {
        HStack(spacing: 6) {
            if !item.isRead {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(Self.metaText(for: item))
                .font(Theme.categoryLabel(12))
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.laterStatus {
        case .saved:
            badge("bookmark.fill")
        case .readLater:
            badge("clock.fill")
        case .regular:
            EmptyView()
        }
    }

    private func badge(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Theme.accentSecondary, in: Circle())
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if !item.isRead { parts.append("Ongelezen") }
        parts.append(item.title)
        parts.append(Self.metaText(for: item))
        switch item.laterStatus {
        case .saved: parts.append("Bewaard")
        case .readLater: parts.append("In Lees later")
        case .regular: break
        }
        return parts.joined(separator: ". ")
    }

    private func loadImage() async {
        guard showImages, localImage == nil else { return }
        if let imageURL {
            let loaded = await ArticleImageService.shared.image(for: imageURL)
            if Task.isCancelled { return }
            image = loaded
            imageFailed = loaded == nil
        } else {
            await ArticleImageService.shared.lookUpImageIfNeeded(for: item, context: modelContext)
        }
    }

    // MARK: Teksten

    /// "BRON · 2 uur geleden · 4 min". Leestijd alleen als de feedtekst lang genoeg is om er
    /// iets over te zeggen; een samenvatting van drie zinnen is geen leestijd.
    static func metaText(for item: FeedItem, now: Date = .now) -> String {
        var parts: [String] = []
        if let source = item.sourceTitle, !source.isEmpty { parts.append(source.uppercased()) }
        if let date = item.effectiveDate { parts.append(relativeTime(for: date, now: now)) }
        if let minutes = readingMinutes(for: item.plainDescription) { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }

    static func readingMinutes(for text: String, wordsPerMinute: Int = 200) -> Int? {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words >= 150 else { return nil }
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relativeTime(for date: Date, now: Date = .now) -> String {
        guard abs(date.timeIntervalSince(now)) >= 60 else { return "zojuist" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Leesmarkering

/// De lijn tussen nieuwe en al geziene artikelen (#225, schets 2C).
struct ReadingMarkerDivider: View {
    let marker: Date

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                line
                Text("Nieuw sinds \(marker.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentSecondary)
                    .fixedSize()
                line
            }
            Text("Hier was je gebleven")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hier was je gebleven. Hierboven staat wat nieuw is sinds je laatste bezoek.")
    }

    private var line: some View {
        Rectangle().fill(Theme.accentSecondary.opacity(0.5)).frame(height: 1)
    }
}

/// Zwevende knop "↑ Markeer alles hierboven als gelezen", met ongedaan maken (#225).
struct MarkAboveAsReadOverlay: View {
    @Environment(\.modelContext) private var modelContext
    /// De artikelen boven de lijn.
    let itemsAbove: [FeedItem]

    @State private var undoItems: [FeedItem] = []

    private var unreadAbove: [FeedItem] { itemsAbove.filter { !$0.isRead } }

    var body: some View {
        Group {
            if !undoItems.isEmpty {
                HStack(spacing: 12) {
                    Text("\(undoItems.count) als gelezen gemarkeerd")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Button("Ongedaan maken") {
                        for item in undoItems { item.isRead = false }
                        modelContext.saveOrLog("de gelezen-markering terug te draaien")
                        undoItems = []
                    }
                    .fontWeight(.semibold)
                }
                .padding(14)
                .background(.regularMaterial, in: Capsule())
                .task(id: undoItems.count) {
                    try? await Task.sleep(for: .seconds(6))
                    undoItems = []
                }
            } else if !unreadAbove.isEmpty {
                Button {
                    let marked = unreadAbove
                    for item in marked { item.isRead = true }
                    modelContext.saveOrLog("de artikelen als gelezen te markeren")
                    undoItems = marked
                } label: {
                    Label("Markeer alles hierboven als gelezen", systemImage: "arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accentSecondary, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .accessibilityHint("Markeert \(unreadAbove.count) nieuwe artikelen als gelezen")
            }
        }
        .padding(.horizontal, 16)
        // Boven de zwevende tabbalk.
        .padding(.bottom, 84)
        .animation(.easeInOut(duration: 0.2), value: undoItems.isEmpty)
    }
}
