import SwiftData
import SwiftUI

// Gedeelde acties voor Lees later en Bewaard (#224), zodat elke artikellijst dezelfde
// icoontjes, teksten en VoiceOver-labels gebruikt: 🕐 `clock` voor de snelle leesstapel,
// 🔖 `bookmark` voor het bewuste archief.

extension View {
    /// Veeg naar rechts: in of uit Lees later. Een bewaard artikel krijgt geen veegactie;
    /// dat staat al in het archief en hoort niet terug in de leesstapel.
    func readLaterSwipe(_ item: FeedItem, melding: Binding<OpslagFoutmelding?>) -> some View {
        modifier(ReadLaterSwipe(item: item, melding: melding))
    }
}

private struct ReadLaterSwipe: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let item: FeedItem
    @Binding var melding: OpslagFoutmelding?

    func body(content: Content) -> some View {
        content.swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !item.isSaved {
                Button {
                    LaterActions.toggleReadLater(item, context: modelContext, melding: &melding)
                } label: {
                    Label(
                        item.readLaterAddedAt != nil ? "Uit Lees later" : "Lees later",
                        systemImage: item.readLaterAddedAt != nil ? "clock.badge.xmark" : "clock"
                    )
                }
                .tint(Theme.accentSecondary)
            }
        }
    }
}

/// Knoppen voor het contextmenu (lang indrukken) van een artikel.
struct LaterContextMenuButtons: View {
    @Environment(\.modelContext) private var modelContext
    let item: FeedItem
    @Binding var melding: OpslagFoutmelding?

    var body: some View {
        Button {
            LaterActions.toggleSaved(item, context: modelContext, melding: &melding)
        } label: {
            Label(
                item.isSaved ? "Verwijder uit Bewaard" : "Bewaren",
                systemImage: item.isSaved ? "bookmark.slash" : "bookmark"
            )
        }
        if !item.isSaved {
            Button {
                LaterActions.toggleReadLater(item, context: modelContext, melding: &melding)
            } label: {
                Label(
                    item.readLaterAddedAt != nil ? "Uit Lees later" : "Lees later",
                    systemImage: item.readLaterAddedAt != nil ? "clock.badge.xmark" : "clock"
                )
            }
        }
    }
}

@MainActor
enum LaterActions {
    static func toggleReadLater(_ item: FeedItem, context: ModelContext, melding: inout OpslagFoutmelding?) {
        if item.readLaterAddedAt != nil {
            ReadLater.removeFromReadLater(item)
        } else {
            ReadLater.addToReadLater(item)
        }
        context.saveOrReport("de Lees later-status van het artikel te wijzigen", melding: &melding)
    }

    /// Bewaren met lokale kopie van tekst en afbeelding; of weer uit Bewaard halen.
    static func toggleSaved(
        _ item: FeedItem, contentHTML: String? = nil, deleteOrphan: Bool = true, context: ModelContext,
        melding: inout OpslagFoutmelding?
    ) {
        if item.isSaved {
            ReadLater.unsave(item, context: context, deleteOrphan: deleteOrphan)
            context.saveOrReport("het artikel uit Bewaard te halen", melding: &melding)
        } else {
            save(item, contentHTML: contentHTML, context: context, melding: &melding)
        }
    }

    static func save(
        _ item: FeedItem, contentHTML: String? = nil, context: ModelContext, melding: inout OpslagFoutmelding?
    ) {
        ReadLater.save(item, contentHTML: contentHTML)
        guard context.saveOrReport("het artikel te bewaren", melding: &melding) else { return }
        Task { await ReadLater.storeImage(for: item, context: context) }
    }
}
