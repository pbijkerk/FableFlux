import SwiftUI
import SwiftData

struct TopicEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let topic: Topic?

    @State private var name = ""
    @State private var keywordsText = ""
    @State private var isLiked = true
    @State private var newKeyword = ""
    @State private var opslagFout: OpslagFoutmelding?

    private var isEditing: Bool { topic != nil }

    var keywords: [String] {
        keywordsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                likedSection
                addKeywordSection
                keywordListSection
            }
            .navigationTitle(isEditing ? "Onderwerp bewerken" : "Nieuw onderwerp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaren") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadTopic() }
            .opslagFoutmelding($opslagFout)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Naam") {
            TextField("bijv. Kunstmatige intelligentie", text: $name)
        }
    }

    private var likedSection: some View {
        Section {
            Toggle("Markeer als favoriet", isOn: $isLiked)
        } footer: {
            Text("Favoriete onderwerpen krijgen voorrang in je samenvattingen.")
        }
    }

    private var addKeywordSection: some View {
        Section {
            HStack {
                TextField("Trefwoord toevoegen…", text: $newKeyword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { addKeyword() }
                Button("Toevoegen", action: addKeyword)
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Trefwoorden")
        } footer: {
            Text("Artikelen met deze trefwoorden worden onder dit onderwerp gegroepeerd.")
        }
    }

    private var keywordListSection: some View {
        Section {
            if keywords.isEmpty {
                Text("Nog geen trefwoorden")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(keywords, id: \.self) { kw in
                    HStack {
                        Label(kw, systemImage: "tag")
                            .font(.callout)
                        Spacer()
                        Button {
                            removeKeyword(kw)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    var updated = keywords
                    updated.remove(atOffsets: indexSet)
                    keywordsText = updated.joined(separator: ", ")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadTopic() {
        guard let topic else { return }
        name = topic.name
        keywordsText = topic.keywords.joined(separator: ", ")
        isLiked = topic.isLiked
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty, !keywords.contains(kw) else { return }
        keywordsText = keywordsText.isEmpty ? kw : keywordsText + ", \(kw)"
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        keywordsText = keywords.filter { $0 != kw }.joined(separator: ", ")
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let topic {
            topic.name = trimmedName
            topic.keywords = keywords
            topic.isLiked = isLiked
            topic.isUserDefined = true
        } else {
            let newTopic = Topic(
                name: trimmedName,
                keywords: keywords,
                isLiked: isLiked,
                isUserDefined: true
            )
            modelContext.insert(newTopic)
        }
        guard modelContext.saveOrReport("het onderwerp te bewaren", melding: &opslagFout) else { return }
        dismiss()
    }
}
