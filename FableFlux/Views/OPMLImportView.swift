import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OPMLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingFeeds: [Feed]

    var refreshService: FeedRefreshService
    var onImported: () -> Void

    @State private var parsedFeeds: [OPMLFeed] = []
    @State private var selectedFeeds: Set<Int> = []
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importComplete = false
    @State private var errorMessage: String?
    @State private var opslagFout: OpslagFoutmelding?

    var body: some View {
        NavigationStack {
            Group {
                if parsedFeeds.isEmpty {
                    pickFileView
                } else {
                    feedSelectionView
                }
            }
            .navigationTitle("OPML importeren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                if !parsedFeeds.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Importeer (\(selectedFeeds.count))") {
                            Task { await importSelected() }
                        }
                        .disabled(selectedFeeds.isEmpty || isImporting)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleFilePickerResult(result)
            }
            .opslagFoutmelding($opslagFout)
        }
    }

    private var pickFileView: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Kies een OPML-bestand")
                .font(.title2.bold())
            Text("Kies een OPML-bestand dat je uit een andere RSS-lezer hebt geëxporteerd.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            Button("Bestand kiezen") {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var feedSelectionView: some View {
        List {
            Section {
                HStack {
                    Button(selectedFeeds.count == parsedFeeds.count ? "Niets selecteren" : "Alles selecteren") {
                        if selectedFeeds.count == parsedFeeds.count {
                            selectedFeeds = []
                        } else {
                            selectedFeeds = Set(parsedFeeds.indices)
                        }
                    }
                    Spacer()
                    Text("\(parsedFeeds.count) \(parsedFeeds.count == 1 ? "feed" : "feeds") gevonden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Feeds") {
                ForEach(Array(parsedFeeds.enumerated()), id: \.offset) { index, feed in
                    let isDuplicate = existingFeeds.contains(where: { $0.url == feed.xmlURL })
                    HStack {
                        Image(systemName: selectedFeeds.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedFeeds.contains(index) ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.title)
                                .lineLimit(1)
                                .foregroundStyle(isDuplicate ? .secondary : .primary)
                            Text(feed.xmlURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if isDuplicate {
                                Text("Al toegevoegd")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedFeeds.contains(index) {
                            selectedFeeds.remove(index)
                        } else {
                            selectedFeeds.insert(index)
                        }
                    }
                }
            }

            if isImporting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Feeds importeren…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let parser = OPMLParser()
            let feeds = parser.parse(data: data)

            if feeds.isEmpty {
                errorMessage = "Geen feeds gevonden in dit bestand. Controleer of het een geldig OPML-bestand is."
            } else {
                parsedFeeds = feeds
                selectedFeeds = Set(
                    feeds.indices.filter { idx in
                        !existingFeeds.contains(where: { $0.url == feeds[idx].xmlURL })
                    })
            }
        } catch {
            errorMessage = "Bestand kon niet worden gelezen: \(error.localizedDescription)"
        }
    }

    private func importSelected() async {
        isImporting = true
        let feedsToImport = selectedFeeds.sorted().map { parsedFeeds[$0] }

        for opmlFeed in feedsToImport {
            guard !existingFeeds.contains(where: { $0.url == opmlFeed.xmlURL }) else { continue }
            let feed = Feed(url: opmlFeed.xmlURL, title: opmlFeed.title)
            // Assign to OPML folder if present
            if let folderName = opmlFeed.folderName, !folderName.isEmpty {
                feed.folder = getOrCreateFolder(name: folderName)
            }
            modelContext.insert(feed)
            await refreshService.refresh(feed: feed, context: modelContext)
        }

        let bewaard = modelContext.saveOrReport("de feeds te importeren", melding: &opslagFout)
        isImporting = false
        onImported()
        // Bij een mislukte import blijft het scherm open, zodat de melding leesbaar is
        // en de gebruiker het opnieuw kan proberen.
        guard bewaard else { return }
        dismiss()
    }

    private func getOrCreateFolder(name: String) -> FeedFolder {
        let descriptor = FetchDescriptor<FeedFolder>(
            predicate: #Predicate { $0.name == name }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let allDescriptor = FetchDescriptor<FeedFolder>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(allDescriptor).first?.sortOrder) ?? -1
        let folder = FeedFolder(name: name, sortOrder: maxOrder + 1, isSystem: false)
        modelContext.insert(folder)
        return folder
    }
}
