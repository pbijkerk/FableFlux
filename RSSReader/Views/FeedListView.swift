import SwiftUI
import Combine
import CoreData
import SwiftData

struct FeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedFolder.sortOrder) private var folders: [FeedFolder]
    @Query(sort: \Feed.title) private var feeds: [Feed]

    var refreshService: FeedRefreshService
    var onRefreshComplete: () async -> Void

    @State private var showAddFeed = false
    @State private var showOPMLImport = false
    @State private var showFolderManagement = false
    @State private var feedToDelete: Feed?
    @State private var showDeleteConfirm = false
    @AppStorage("uncategorizedExpanded") private var uncategorizedExpanded = true
    @State private var feedForSettings: Feed? = nil
    @State private var editMode: EditMode = .inactive
    @State private var opslagFout: OpslagFoutmelding?
    @AppStorage(AppConfiguration.UserDefaultsKeys.feedCountMode) private var feedCountMode = "total"
    @AppStorage(AppConfiguration.UserDefaultsKeys.appTheme) private var appTheme = AppTheme.standaard.rawValue
    /// Teller per feed, via `FeedBadgeCounter` in plaats van `feed.items` (#121).
    @State private var badgeCounts: [UUID: Int] = [:]
    @State private var isVisible = false
    @State private var badgeUpdateTask: Task<Void, Never>?

    var uncategorized: [Feed] {
        feeds.filter { $0.folder == nil }
    }

    var body: some View {
        Group {
            if feeds.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Feeds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Alles rechts: als pushbestemming is de leading-plek van de terugknop.
            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .active {
                    Button("Gereed") {
                        withAnimation { editMode = .inactive }
                    }
                } else if refreshService.isRefreshing {
                    ProgressView()
                } else {
                    Button("Vernieuwen", systemImage: "arrow.clockwise") {
                        Task { await refreshFeeds() }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Feed toevoegen", systemImage: "plus") {
                        showAddFeed = true
                    }
                    Button("OPML importeren", systemImage: "square.and.arrow.down") {
                        showOPMLImport = true
                    }
                    Divider()
                    Button("Folders beheren", systemImage: "folder.badge.gear") {
                        showFolderManagement = true
                    }
                    Button("Volgorde wijzigen", systemImage: "arrow.up.arrow.down") {
                        withAnimation { editMode = .active }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedView(refreshService: refreshService) {
                Task { await onRefreshComplete() }
            }
        }
        .sheet(isPresented: $showOPMLImport) {
            OPMLImportView(refreshService: refreshService) {
                Task { await onRefreshComplete() }
            }
        }
        .sheet(isPresented: $showFolderManagement) {
            FolderManagementView()
        }
        .alert("Feed verwijderen", isPresented: $showDeleteConfirm, presenting: feedToDelete) { feed in
            Button("Verwijderen", role: .destructive) { delete(feed: feed) }
            Button("Annuleren", role: .cancel) {}
        } message: { feed in
            Text("Wil je \"\(feed.title)\" en alle artikelen verwijderen?")
        }
        .opslagFoutmelding($opslagFout)
        // Alleen bijwerken zolang de lijst in beeld is; bij terugkeer opnieuw tellen.
        .onAppear {
            isVisible = true
            updateBadgeCounts()
        }
        .onDisappear {
            isVisible = false
            badgeUpdateTask?.cancel()
        }
        .onChange(of: feedCountMode) { updateBadgeCounts() }
        .onChange(of: feeds.count) { updateBadgeCounts() }
        // `ModelContext.didSave` komt op iOS 17 niet door; de onderliggende Core Data-
        // melding wel. Die komt soms meermaals per opslag, vandaar de samenvoeging.
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                .receive(on: RunLoop.main)
        ) { _ in
            if isVisible { scheduleBadgeUpdate() }
        }
    }

    private func scheduleBadgeUpdate() {
        badgeUpdateTask?.cancel()
        badgeUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            updateBadgeCounts()
        }
    }

    private func updateBadgeCounts() {
        badgeCounts = FeedBadgeCounter.counts(
            for: feeds, unreadOnly: feedCountMode == "unread", context: modelContext
        )
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Nog geen feeds")
                .font(.title2.bold())
            Text("Voeg RSS-feeds toe of importeer een OPML-bestand.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Button("Feed toevoegen") { showAddFeed = true }
                    .buttonStyle(.borderedProminent)
                Button("OPML importeren") { showOPMLImport = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var feedList: some View {
        List {
            ForEach(folders) { folder in
                folderSection(folder)
            }
            .onMove(perform: moveFolders)

            if !uncategorized.isEmpty {
                Section {
                    if uncategorizedExpanded {
                        ForEach(uncategorized) { feed in
                            feedRow(feed)
                        }
                    }
                } header: {
                    SectionHeaderView(
                        title: "Overig",
                        icon: "tray",
                        count: uncategorized.count,
                        isExpanded: $uncategorizedExpanded
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(.default, value: folders.map { $0.id })
        .refreshable { await refreshFeeds() }
        .environment(\.editMode, $editMode)
    }

    @ViewBuilder
    private func folderSection(_ folder: FeedFolder) -> some View {
        let isExpanded = Binding(
            get: { folder.isExpanded },
            set: {
                folder.isExpanded = $0
                modelContext.saveOrLog("de uitklapstand van de folder te bewaren")
            }
        )
        let sortedFeeds = folder.feeds.sorted { $0.title < $1.title }

        Section {
            if isExpanded.wrappedValue {
                ForEach(sortedFeeds) { feed in
                    feedRow(feed)
                }
            }
        } header: {
            SectionHeaderView(
                title: folder.name,
                icon: folder.icon,
                count: folder.feeds.count,
                isExpanded: isExpanded,
                folder: folder
            )
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: Feed) -> some View {
        NavigationLink(destination: FeedItemsView(feed: feed, refreshService: refreshService)) {
            FeedRowView(feed: feed, badgeCount: badgeCounts[feed.id])
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                feedToDelete = feed
                showDeleteConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    await refreshService.refresh(feed: feed, context: modelContext)
                    await onRefreshComplete()
                }
            } label: {
                Label("Vernieuwen", systemImage: "arrow.clockwise")
            }
            .tint(AppTheme(storedValue: appTheme).accent)
        }
        .contextMenu {
            Menu("Verplaats naar folder") {
                Button {
                    feed.folder = nil
                    modelContext.saveOrReport("de feed uit de folder te halen", melding: &opslagFout)
                } label: {
                    Label("Overig (geen folder)", systemImage: "tray")
                }
                Divider()
                ForEach(folders) { folder in
                    Button {
                        feed.folder = folder
                        modelContext.saveOrReport("de feed naar de folder te verplaatsen", melding: &opslagFout)
                    } label: {
                        Label(folder.name, systemImage: folder.icon)
                    }
                }
            }
            Divider()
            Button {
                feedForSettings = feed
            } label: {
                Label("Instellingen", systemImage: "gearshape")
            }
        }
        .sheet(item: $feedForSettings) { feed in
            FeedSettingsView(feed: feed) {
                // Nieuwe clustering-ronde, zodat Vandaag de gewijzigde instelling toont.
                await onRefreshComplete()
            }
        }
    }

    private func refreshFeeds() async {
        await refreshService.refreshAll(feeds: feeds, context: modelContext)
        await onRefreshComplete()
    }

    private func delete(feed: Feed) {
        modelContext.delete(feed)
        modelContext.saveOrReport("de feed te verwijderen", melding: &opslagFout)
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
        modelContext.saveOrReport("de volgorde van de folders te bewaren", melding: &opslagFout)
    }
}

struct SectionHeaderView: View {
    let title: String
    let icon: String
    let count: Int
    @Binding var isExpanded: Bool
    var folder: FeedFolder? = nil

    @AppStorage(AppConfiguration.UserDefaultsKeys.feedListScale)
    private var feedListScale = AppConfiguration.defaultFeedListScale

    private var iconSize: CGFloat { 15 * feedListScale }
    private var iconFrame: CGFloat { 20 * feedListScale }
    private var titleFont: Font { .system(size: 15 * feedListScale, weight: .bold) }
    private var captionFont: Font { .system(size: 12 * feedListScale, weight: .regular) }
    private var captionBoldFont: Font { .system(size: 12 * feedListScale, weight: .bold) }

    var body: some View {
        HStack(spacing: 8) {
            if let folder {
                NavigationLink(destination: FolderItemsView(folder: folder)) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: iconSize))
                            .foregroundStyle(.tint)
                            .frame(width: iconFrame)
                        Text(title)
                            .font(titleFont)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(.tint)
                    .frame(width: iconFrame)
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(captionBoldFont)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct FeedRowView: View {
    let feed: Feed
    /// Berekend door `FeedListView` met een `fetchCount`; `nil` zolang die nog niet klaar is.
    let badgeCount: Int?
    @AppStorage(AppConfiguration.UserDefaultsKeys.feedCountMode) private var feedCountMode = "total"
    @AppStorage(AppConfiguration.UserDefaultsKeys.feedListScale) private var feedListScale = AppConfiguration
        .defaultFeedListScale

    private var brand: Color { Theme.brandColor(for: feed.title.isEmpty ? feed.url : feed.title) }

    private var faviconSize: CGFloat { 30 * feedListScale }
    private var faviconRadius: CGFloat { 7 * feedListScale }
    private var titleFont: Font { .system(size: 17 * feedListScale, weight: .semibold, design: .rounded) }
    private var urlFont: Font { .system(size: 12 * feedListScale) }
    private var badgeFont: Font { .system(size: 12 * feedListScale, weight: .bold) }
    private var dateFont: Font { .system(size: 11 * feedListScale) }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: feed.faviconImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14 * feedListScale))
                        .foregroundStyle(brand)
                @unknown default:
                    brand.opacity(0.2)
                }
            }
            .frame(width: faviconSize, height: faviconSize)
            .clipShape(RoundedRectangle(cornerRadius: faviconRadius, style: .continuous))
            .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: faviconRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(titleFont)
                    .lineLimit(1)
                Text(feed.url)
                    .font(urlFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let badgeCount, feedCountMode == "total" || badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(badgeFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(brand, in: Capsule())
                }
                if let date = feed.lastRefreshed {
                    Text(date, style: .relative)
                        .font(dateFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Telt de artikelen per feed met `fetchCount` (#121). `FeedRowView` las hiervoor
/// `feed.items`, wat per feed de hele relatie laadde en in de stand "ongelezen" ook elk
/// artikel afzonderlijk, en dat bij elke wijziging opnieuw voor alle feeds.
enum FeedBadgeCounter {
    static func counts(for feeds: [Feed], unreadOnly: Bool, context: ModelContext) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for feed in feeds {
            let feedID = feed.id
            let descriptor =
                unreadOnly
                ? FetchDescriptor<FeedItem>(predicate: #Predicate { $0.feed?.id == feedID && !$0.isRead })
                : FetchDescriptor<FeedItem>(predicate: #Predicate { $0.feed?.id == feedID })
            // Een mislukte telling laat de badge weg in plaats van een verkeerd getal te tonen.
            result[feedID] = try? context.fetchCount(descriptor)
        }
        return result
    }
}
