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

    /// Zoektekst voor het filteren van bewaarde items op tag (#215). Matcht op items
    /// waarvan minstens één tag de zoektekst bevat, hoofdletterongevoelig.
    @State private var searchText = ""

    /// Bewaarde items gefilterd op `searchText`. Filteren gebeurt in Swift, niet in de
    /// SwiftData-`#Predicate` van `@Query`: die ondersteunt geen `contains`-closure op
    /// een array-eigenschap. De lijst is persoonlijk-gebruik-schaal, dus dat kost niets.
    private var filteredItems: [FeedItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return savedItems }
        return savedItems.filter { item in
            item.effectiveTags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedItems.isEmpty {
                    ContentUnavailableView(
                        "Geen bewaarde artikelen",
                        systemImage: "bookmark",
                        description: Text("Swipe een artikel naar rechts om het te bewaren.")
                    )
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ZStack {
                                FeedItemCard(item: item)
                                NavigationLink(destination: ArticlePageView(items: filteredItems, initialIndex: index))
                                {
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
            .searchable(text: $searchText, prompt: "Zoek op tag")
            .opslagFoutmelding($opslagFout)
        }
    }
}
