import SwiftUI
import SwiftData

struct FolderItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppConfiguration.UserDefaultsKeys.hideReadArticles) private var hideReadArticles = false
    let folder: FeedFolder

    @State private var viewMode: ViewMode = .timeline
    @State private var eventClusters: [EventCluster] = []
    @State private var expandedClusters: Set<UUID> = []
    @State private var isClustering = false
    @State private var opslagFout: OpslagFoutmelding?
    @State private var geopend: MapArtikel?

    enum ViewMode { case timeline, events }

    var sortedItems: [FeedItem] {
        folder.feeds
            .flatMap { $0.items }
            .filter { hideReadArticles ? !$0.isRead : true }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if viewMode == .timeline {
                timelineList
            } else {
                eventsView
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationDestination(item: $geopend) { artikel in
            VastgelegdeArtikelPagina(id: artikel.id, items: artikel.lijst)
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Weergave", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.timeline)
                    Image(systemName: "square.3.layers.3d").tag(ViewMode.events)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
        }
        .task(id: viewMode) {
            if viewMode == .events { await buildClusters() }
        }
        .opslagFoutmelding($opslagFout)
    }

    // MARK: - Timeline

    private var timelineList: some View {
        List {
            ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                itemRow(item: item, allItems: sortedItems, index: index)
            }
        }
    }

    // MARK: - Events

    private var eventsView: some View {
        List {
            if isClustering {
                HStack {
                    ProgressView()
                    Text("Gebeurtenissen zoeken…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if eventClusters.isEmpty {
                ContentUnavailableView(
                    "Geen gemeenschappelijke onderwerpen",
                    systemImage: "square.3.layers.3d.slash",
                    description: Text("Er zijn geen artikelen gevonden die door meerdere bronnen worden besproken.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(eventClusters) { cluster in
                    Section {
                        if expandedClusters.contains(cluster.id) {
                            let allExpanded = cluster.items
                            ForEach(Array(allExpanded.enumerated()), id: \.element.id) { index, item in
                                itemRow(item: item, allItems: allExpanded, index: index)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    } header: {
                        StoryGroupHeaderView(
                            cluster: cluster,
                            isExpanded: expandedClusters.contains(cluster.id)
                        ) {
                            withAnimation(.spring(duration: 0.25)) {
                                if expandedClusters.contains(cluster.id) {
                                    expandedClusters.remove(cluster.id)
                                } else {
                                    expandedClusters.insert(cluster.id)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: - Shared item row

    @ViewBuilder
    private func itemRow(item: FeedItem, allItems: [FeedItem], index: Int) -> some View {
        // Selectie in plaats van een NavigationLink: zie `FeedItemsView` (#139).
        Button {
            geopend = MapArtikel(id: item.id, lijst: allItems)
        } label: {
            FeedItemCard(item: item)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                item.isRead.toggle()
                modelContext.saveOrLog("de gelezen-markering te bewaren")
            } label: {
                Label(
                    item.isRead ? "Ongelezen" : "Gelezen",
                    systemImage: item.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                item.isSaved.toggle()
                modelContext.saveOrReport("de bewaarstatus van het artikel te wijzigen", melding: &opslagFout)
            } label: {
                Label(
                    item.isSaved ? "Niet bewaard" : "Bewaar",
                    systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
            }
            .tint(Theme.accentSecondary)
        }
    }

    // MARK: - Clustering

    private func buildClusters() async {
        isClustering = true
        defer { isClustering = false }
        let items = sortedItems
        let clusters = EventClusteringService.shared.cluster(items: items)
        eventClusters = clusters
        // Openklap de eerste cluster automatisch
        if let first = clusters.first {
            expandedClusters = [first.id]
        }
    }
}

/// Het geopende artikel in `FolderItemsView`, voor `navigationDestination(item:)`. Draagt
/// de lijst waar het artikel uit komt mee: de tijdlijn of de artikelen van de opengeklapte
/// gebeurtenissen.
struct MapArtikel: Hashable {
    let id: UUID
    let lijst: [FeedItem]
}
