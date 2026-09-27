import SwiftUI
import SwiftData

struct TopicsManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.name) private var topics: [Topic]

    @State private var showAddTopic = false
    @State private var topicToEdit: Topic?
    @State private var opslagFout: OpslagFoutmelding?

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
        }
        .sheet(isPresented: $showAddTopic) {
            TopicEditView(topic: nil)
        }
        .sheet(item: $topicToEdit) { topic in
            TopicEditView(topic: topic)
        }
        .opslagFoutmelding($opslagFout)
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
