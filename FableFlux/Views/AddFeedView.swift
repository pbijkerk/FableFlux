import SwiftUI
import SwiftData

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var refreshService: FeedRefreshService
    var onAdded: () -> Void

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed URL") {
                    TextField("https://example.com/feed.xml", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: addFeed) {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Feed controleren…")
                            }
                        } else {
                            Text("Feed toevoegen")
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Feed toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
            }
        }
    }

    private func addFeed() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // FeedAddingService (#201) doet validatie + opslag; dezelfde functie wordt
                // gebruikt door FableFluxShareExtension en kan door #203 worden hergebruikt.
                let feed = try await FeedAddingService.addFeed(from: urlText, context: modelContext)
                // Volledige verversing erbovenop: bronbeoordeling, mapindeling en consistente
                // ontdubbeling, zoals bij elke reguliere refresh.
                await refreshService.refresh(feed: feed, context: modelContext)
                onAdded()
                dismiss()
            } catch let error as FeedAddError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "Feed kon niet worden geladen: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
