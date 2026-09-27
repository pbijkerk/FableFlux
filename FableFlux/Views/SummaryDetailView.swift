import SwiftUI
import SwiftData

struct SummaryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var topics: [Topic]

    let cluster: TopicCluster

    private var accent: Color { Theme.brandColor(for: cluster.topicName) }

    @State private var showTopicPrompt = false
    @State private var topicAlreadySaved = false
    @State private var savedTopic: Topic?
    @State private var opslagFout: OpslagFoutmelding?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topicHeader
                TopicSourceRatingView(cluster: cluster)
                if cluster.hasDisputedClaim {
                    FactCheckWarningView(results: cluster.disputedFactChecks)
                }
                summarySection
                articlesSection
            }
            .padding()
        }
        .navigationTitle(cluster.topicName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkIfTopicSaved()
        }
        .task {
            // Use .task so the delay is automatically cancelled if the view disappears
            guard !topicAlreadySaved else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !topicAlreadySaved else { return }
            withAnimation { showTopicPrompt = true }
        }
        .safeAreaInset(edge: .bottom) {
            if showTopicPrompt && !topicAlreadySaved {
                topicPromptBanner
            }
        }
        .opslagFoutmelding($opslagFout)
    }

    private var topicHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(cluster.items.count) articles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if topicAlreadySaved {
                    Label("Saved topic", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if topicAlreadySaved {
                Button {
                    removeTopic()
                } label: {
                    Label("Remove", systemImage: "heart.slash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "doc.text")
                .font(.headline)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(cluster.statements) { statement in
                        StatementRowView(statement: statement, itemsByID: cluster.itemsByID, accent: accent)
                    }
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var articlesSection: some View {
        // Lazy: een topic kan honderden artikelen bevatten. Met een gewone VStack
        // bouwt SwiftUI alle rijen én alle NavigationLink-destinations in één
        // main-thread-pass, wat bij grote topics een zichtbare hang oplevert.
        LazyVStack(alignment: .leading, spacing: 12) {
            Label("Articles in this summary", systemImage: "list.bullet")
                .font(.headline)

            ForEach(cluster.items) { item in
                NavigationLink(destination: ItemDetailView(item: item)) {
                    ArticleRowView(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topicPromptBanner: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Do you like this topic?")
                        .font(.subheadline.bold())
                    Text("Save \"\(cluster.topicName)\" for future summaries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { showTopicPrompt = false }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                Button("Save") {
                    saveTopic()
                    withAnimation { showTopicPrompt = false }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private func checkIfTopicSaved() {
        savedTopic = topics.first { $0.name.lowercased() == cluster.topicName.lowercased() }
        topicAlreadySaved = savedTopic != nil
    }

    private func saveTopic() {
        let topic = Topic(
            name: cluster.topicName,
            keywords: cluster.keywords,
            isLiked: true,
            isUserDefined: false
        )
        modelContext.insert(topic)
        guard modelContext.saveOrReport("het onderwerp te bewaren", melding: &opslagFout) else { return }
        topicAlreadySaved = true
        savedTopic = topic
    }

    private func removeTopic() {
        if let topic = savedTopic {
            modelContext.delete(topic)
            guard modelContext.saveOrReport("het onderwerp te verwijderen", melding: &opslagFout) else { return }
            topicAlreadySaved = false
            savedTopic = nil
        }
    }
}

struct ArticleRowView: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack {
                if let feedTitle = item.feed?.title {
                    Text(feedTitle)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                ReliabilityBadgeView(level: item.feed?.reliabilityLevel)
                Spacer()
                if let date = item.pubDate {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
