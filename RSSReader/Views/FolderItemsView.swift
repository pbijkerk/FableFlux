import SwiftUI
import SwiftData

/// De artikelen van alle feeds in een map.
///
/// Dun omhulsel om `FolderItemsContent`: `@Query` krijgt zijn predicaat bij initialisatie,
/// en `@AppStorage` is daar nog niet beschikbaar. De feeds van de map zijn een lijst van
/// feeds, geen artikelen; die ophalen is goedkoop.
struct FolderItemsView: View {
    @AppStorage(AppConfiguration.UserDefaultsKeys.hideReadArticles) private var hideReadArticles = false
    let folder: FeedFolder

    var body: some View {
        FolderItemsContent(
            folder: folder, feedIDs: folder.feeds.map(\.id), hideRead: hideReadArticles
        )
    }
}

/// Haalt de artikelen met één query op in plaats van `folder.feeds.flatMap { $0.items }`
/// (#136), wat bij elke hertekening alle artikelen van de map afzonderlijk laadde.
private struct FolderItemsContent: View {
    @Environment(\.modelContext) private var modelContext
    let folder: FeedFolder
    @Query private var sortedItems: [FeedItem]

    @State private var viewMode: ViewMode = .timeline
    @State private var eventClusters: [EventCluster] = []
    @State private var expandedClusters: Set<UUID> = []
    @State private var isClustering = false
    @State private var opslagFout: OpslagFoutmelding?

    enum ViewMode { case timeline, events }

    init(folder: FeedFolder, feedIDs: [UUID], hideRead: Bool) {
        self.folder = folder
        _sortedItems = Query(ArticleFilter.descriptor(hideRead: hideRead, feedIDs: feedIDs))
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
        ZStack {
            FeedItemCard(item: item)
            NavigationLink(destination: ArticlePageView(items: allItems, initialIndex: index)) {
                EmptyView()
            }
            .opacity(0)
        }
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
