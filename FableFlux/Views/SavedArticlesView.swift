import SwiftUI
import SwiftData

struct SavedArticlesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<FeedItem> { $0.isSaved },
        sort: \FeedItem.pubDate,
        order: .reverse
    )
    private var savedItems: [FeedItem]

    @State private var opslagFout: OpslagFoutmelding?

    var body: some View {
        NavigationStack {
            Group {
                if savedItems.isEmpty {
                    ContentUnavailableView(
                        "Geen bewaarde artikelen",
                        systemImage: "bookmark",
                        description: Text("Swipe een artikel naar rechts om het te bewaren.")
                    )
                } else {
                    List {
                        ForEach(Array(savedItems.enumerated()), id: \.element.id) { index, item in
                            ZStack {
                                FeedItemCard(item: item)
                                NavigationLink(destination: ArticlePageView(items: savedItems, initialIndex: index)) {
                                    EmptyView()
                                }
                                .opacity(0)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    item.isSaved = false
                                    modelContext.saveOrReport(
                                        "het artikel uit Bewaard te verwijderen", melding: &opslagFout)
                                } label: {
                                    Label("Verwijder", systemImage: "bookmark.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background.ignoresSafeArea())
                }
            }
            .navigationTitle("Bewaard")
            .navigationBarTitleDisplayMode(.inline)
            .opslagFoutmelding($opslagFout)
        }
    }
}
