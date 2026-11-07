import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Tab "Later" (#224): de korte leesstapel (Lees later, met termijn) en het bewuste
/// archief (Bewaard, zonder termijn) naast elkaar, met een schakelaar bovenaan. Zo blijft
/// de tabbalk bij drie tabs.
struct LaterView: View {
    enum LaterSection: String, CaseIterable, Identifiable {
        case readLater = "Lees later"
        case saved = "Bewaard"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<FeedItem> { !$0.isSaved && $0.readLaterAddedAt != nil },
        sort: \FeedItem.readLaterAddedAt,
        order: .reverse
    )
    private var readLaterQuery: [FeedItem]

    @Query(filter: #Predicate<FeedItem> { $0.isSaved })
    private var savedQuery: [FeedItem]

    @AppStorage(AppConfiguration.UserDefaultsKeys.readLaterDays)
    private var termDays = AppConfiguration.defaultReadLaterDays

    @State private var section: LaterSection = .readLater
    @State private var opslagFout: OpslagFoutmelding?
    @State private var showImportPicker = false
    @State private var importMelding: String?

    /// Zoektekst voor Bewaard: filtert op tag (#215), hoofdletterongevoelig.
    @State private var searchText = ""

    /// Verlopen artikelen staan nog in de store tot de volgende opruimronde (bij verversen);
    /// hier vallen ze meteen weg, zodat de lijst de termijn laat zien die je hebt ingesteld.
    private var readLaterItems: [FeedItem] {
        let now = Date()
        return readLaterQuery.filter { !ReadLater.isExpired($0, termDays: termDays, now: now) }
    }

    /// Nieuwste bewaarmoment eerst; artikelen van vóór #224 sorteren op hun eigen datum.
    /// Sorteren en filteren in Swift: `#Predicate` kent geen terugval op een optionele datum
    /// en geen `contains` op een array. Persoonlijke schaal, dus dat kost niets.
    private var savedItems: [FeedItem] {
        let sorted = savedQuery.sorted { $0.savedSortDate > $1.savedSortDate }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { item in
            item.effectiveTags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Lijst", selection: $section) {
                    ForEach(LaterSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch section {
                case .readLater: readLaterList
                case .saved: savedList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Later")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: SavedArticlesExportDocument(
                                data: SavedArticleIO.export(readLaterQuery + savedQuery)),
                            preview: SharePreview("fableflux-bewaard.json")
                        ) {
                            Label("Lees later en Bewaard exporteren", systemImage: "square.and.arrow.up")
                        }
                        Button("Artikelen importeren", systemImage: "square.and.arrow.down") {
                            showImportPicker = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Meer")
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
                "Artikelen importeren",
                isPresented: Binding(get: { importMelding != nil }, set: { if !$0 { importMelding = nil } })
            ) {
                Button("Oké", role: .cancel) {}
            } message: {
                Text(importMelding ?? "")
            }
            .opslagFoutmelding($opslagFout)
        }
    }

    // MARK: - Lees later

    @ViewBuilder
    private var readLaterList: some View {
        let items = readLaterItems
        if items.isEmpty {
            ContentUnavailableView(
                "Niets in Lees later",
                systemImage: "clock",
                description: Text(
                    termDays > 0
                        ? "Veeg een artikel naar rechts om het later te lezen. Het blijft \(termDays) dagen staan."
                        : "Veeg een artikel naar rechts om het later te lezen.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        articleLink(item, in: items, index: index)
                        ReadLaterTermRow(item: item, termDays: termDays, melding: $opslagFout)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            ReadLater.removeFromReadLater(item)
                            modelContext.saveOrReport("het artikel uit Lees later te halen", melding: &opslagFout)
                        } label: {
                            Label("Uit Lees later", systemImage: "clock.badge.xmark")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            LaterActions.save(item, context: modelContext, melding: &opslagFout)
                        } label: {
                            Label("Bewaren", systemImage: "bookmark")
                        }
                        .tint(Theme.accentSecondary)
                    }
                    .contextMenu { LaterContextMenuButtons(item: item, melding: $opslagFout) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Bewaard

    @ViewBuilder
    private var savedList: some View {
        let items = savedItems
        Group {
            if savedQuery.isEmpty {
                ContentUnavailableView(
                    "Geen bewaarde artikelen",
                    systemImage: "bookmark",
                    description: Text(
                        "Bewaar een artikel via het bladwijzer-icoon in het leesscherm, of houd het ingedrukt.")
                )
                .frame(maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 6) {
                            articleLink(item, in: items, index: index)
                            if item.savedContentHTML != nil {
                                Label("Offline leesbaar", systemImage: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Offline leesbaar")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                ReadLater.unsave(item, context: modelContext)
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
            }
        }
        .searchable(text: $searchText, prompt: "Zoek op tag")
    }

    // MARK: - Gedeeld

    private func articleLink(_ item: FeedItem, in items: [FeedItem], index: Int) -> some View {
        ZStack {
            FeedItemCard(item: item)
            NavigationLink(destination: ArticlePageView(items: items, initialIndex: index)) {
                EmptyView()
            }
            .opacity(0)
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
        guard modelContext.saveOrReport("de artikelen te importeren", melding: &opslagFout) else { return }
        importMelding =
            added == 0
            ? "Geen nieuwe artikelen gevonden — mogelijk stonden ze er al."
            : "\(added) artikel\(added == 1 ? "" : "en") geïmporteerd."
    }
}

/// Termijnlabel onder een Lees later-kaart: "nog X d", en binnen het waarschuwingsvenster
/// de chip "verloopt over X dagen" met Verlengen en Bewaren (#224). Geen pushmeldingen.
private struct ReadLaterTermRow: View {
    @Environment(\.modelContext) private var modelContext
    let item: FeedItem
    let termDays: Int
    @Binding var melding: OpslagFoutmelding?

    var body: some View {
        if let left = ReadLater.daysLeft(item, termDays: termDays) {
            if ReadLater.isInWarningWindow(item, termDays: termDays) {
                HStack(spacing: 8) {
                    Label(Self.expiryText(left), systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentSecondary)
                    Spacer(minLength: 0)
                    Button("Verlengen") {
                        ReadLater.extend(item)
                        modelContext.saveOrReport("de termijn te verlengen", melding: &melding)
                    }
                    .accessibilityHint("Zet de termijn opnieuw op \(termDays) dagen")
                    Button("Bewaren") {
                        LaterActions.save(item, context: modelContext, melding: &melding)
                    }
                    .accessibilityHint("Zet het artikel in Bewaard, zonder termijn")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("nog \(left) d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Nog \(left) \(left == 1 ? "dag" : "dagen") in Lees later")
            }
        }
    }

    static func expiryText(_ days: Int) -> String {
        switch days {
        case 0: return "verloopt vandaag"
        case 1: return "verloopt over 1 dag"
        default: return "verloopt over \(days) dagen"
        }
    }
}
