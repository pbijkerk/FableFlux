import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TopicsManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.name) private var topics: [Topic]

    @State private var showAddTopic = false
    @State private var topicToEdit: Topic?
    @State private var opslagFout: OpslagFoutmelding?
    @State private var showImportPicker = false
    @State private var importMelding: String?

    var body: some View {
        Group {
            if topics.isEmpty {
                emptyState
            } else {
                topicList
            }
        }
        .navigationTitle("Onderwerpen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Onderwerp toevoegen", systemImage: "plus") {
                    showAddTopic = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: TopicExportDocument(data: TopicIO.export(topics)),
                        preview: SharePreview("fableflux-onderwerpen.json")
                    ) {
                        Label("Onderwerpen exporteren", systemImage: "square.and.arrow.up")
                    }
                    Button("Onderwerpen importeren", systemImage: "square.and.arrow.down") {
                        showImportPicker = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddTopic) {
            TopicEditView(topic: nil)
        }
        .sheet(item: $topicToEdit) { topic in
            TopicEditView(topic: topic)
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Onderwerpen importeren",
            isPresented: Binding(get: { importMelding != nil }, set: { if !$0 { importMelding = nil } })
        ) {
            Button("Oké", role: .cancel) {}
        } message: {
            Text(importMelding ?? "")
        }
        .opslagFoutmelding($opslagFout)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importMelding = "Het bestand kon niet worden gelezen."
            return
        }
        let added = TopicIO.importTopics(from: data, existing: topics, context: modelContext)
        guard modelContext.saveOrReport("de onderwerpen te importeren", melding: &opslagFout) else { return }
        importMelding =
            added == 0
            ? "Geen nieuwe onderwerpen gevonden — mogelijk stonden ze al in de lijst."
            : "\(added) onderwerp\(added == 1 ? "" : "en") geïmporteerd."
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tag")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Nog geen onderwerpen")
                .font(.title2.bold())
            Text(
                "Onderwerpen die je in samenvattingen als favoriet markeert, verschijnen hier. Je kunt ook zelf onderwerpen toevoegen."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            Button("Onderwerp toevoegen") { showAddTopic = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var topicList: some View {
        List {
            ForEach(topics) { topic in
                TopicRowView(topic: topic)
                    .contentShape(Rectangle())
                    .onTapGesture { topicToEdit = topic }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(topic)
                            modelContext.saveOrReport("het onderwerp te verwijderen", melding: &opslagFout)
                        } label: {
                            Label("Verwijderen", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            topic.isLiked.toggle()
                            modelContext.saveOrReport("het onderwerp te wijzigen", melding: &opslagFout)
                        } label: {
                            Label(
                                topic.isLiked ? "Favoriet verwijderen" : "Favoriet maken",
                                systemImage: topic.isLiked ? "heart.slash" : "heart.fill")
                        }
                        .tint(topic.isLiked ? .gray : .pink)
                    }
            }
        }
    }
}

struct TopicRowView: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(topic.name)
                    .font(.headline)
                if topic.isLiked {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !topic.keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(topic.keywords.prefix(8), id: \.self) { kw in
                            Text(kw)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
