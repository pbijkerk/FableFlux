import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SavedArticlesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<FeedItem> { $0.isSaved },
        sort: \FeedItem.pubDate,
        order: .reverse
    )
    private var savedItems: [FeedItem]

    @State private var opslagFout: OpslagFoutmelding?
    @State private var showImportPicker = false
    @State private var importMelding: String?

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: SavedArticlesExportDocument(data: SavedArticleIO.export(savedItems)),
                            preview: SharePreview("fableflux-bewaard.json")
                        ) {
                            Label("Bewaarde artikelen exporteren", systemImage: "square.and.arrow.up")
                        }
                        Button("Bewaarde artikelen importeren", systemImage: "square.and.arrow.down") {
                            showImportPicker = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                "Bewaarde artikelen importeren",
                isPresented: Binding(get: { importMelding != nil }, set: { if !$0 { importMelding = nil } })
            ) {
                Button("Oké", role: .cancel) {}
            } message: {
                Text(importMelding ?? "")
            }
            .opslagFoutmelding($opslagFout)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importMelding = "Het bestand kon niet worden gelezen."
            return
        }
        let added = SavedArticleIO.importArticles(from: data, context: modelContext)
        guard modelContext.saveOrReport("de bewaarde artikelen te importeren", melding: &opslagFout) else { return }
        importMelding =
            added == 0
            ? "Geen nieuwe artikelen gevonden — mogelijk stonden ze al in Bewaard."
            : "\(added) artikel\(added == 1 ? "" : "en") geïmporteerd."
    }
}
