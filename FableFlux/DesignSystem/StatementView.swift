import SwiftUI

/// Eén samenvattingsbewering met haar bronchips — gedeeld door `SummaryListView`
/// (Vandaag-kaarten) en `SummaryDetailView`, zodat de opmaak op één plek staat.
struct StatementRowView: View {
    let statement: SummaryStatement
    let itemsByID: [UUID: FeedItem]
    let accent: Color

    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize)
    private var fontSize = AppConfiguration.defaultArticleFontSize

    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontFamily)
    private var fontFamily = AppConfiguration.defaultArticleFontFamily

    private var font: Font {
        switch fontFamily {
        case "charter": return .custom("Charter", size: CGFloat(fontSize))
        case "newyork": return .custom("New York", size: CGFloat(fontSize))
        case "georgia": return .custom("Georgia", size: CGFloat(fontSize))
        default: return .system(size: CGFloat(fontSize))
        }
    }

    var body: some View {
        let sources = statement.sourceItemIDs.compactMap { itemsByID[$0] }

        VStack(alignment: .leading, spacing: 6) {
            Text(statement.text)
                .font(font)
                .lineSpacing(4)

            if !sources.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(sources) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            SourceChipView(item: item, accent: accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Bronchip met titel, feednaam en betrouwbaarheidsbadge — opent het artikel bij een tik.
struct SourceChipView: View {
    let item: FeedItem
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let feedTitle = item.feed?.title {
                        Text(feedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ReliabilityBadgeView(level: item.feed?.reliabilityLevel)
                }
            }
            .frame(maxWidth: AppConfiguration.summarySourceChipMaxWidth, alignment: .leading)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accent.opacity(0.12), in: Capsule())
    }
}

/// Eenvoudige wrap-layout die subviews op regels plaatst en doorbreekt bij de
/// beschikbare breedte — gebruikt voor de rij bronverwijzingen per bewering.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
