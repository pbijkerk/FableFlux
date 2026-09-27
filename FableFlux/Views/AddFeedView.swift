import SwiftUI
import SwiftData

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var feeds: [Feed]

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
                                Text("Verifying feed…")
                            }
                        } else {
                            Text("Add Feed")
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addFeed() {
        var urlString = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard URL(string: urlString) != nil else {
            errorMessage = "Invalid URL. Please check and try again."
            return
        }

        // Check duplicate
        if feeds.contains(where: { $0.url == urlString }) {
            errorMessage = "This feed is already in your list."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let title = try await refreshService.fetchFeedTitle(url: urlString)
                let feed = Feed(url: urlString, title: title)
                modelContext.insert(feed)
                try modelContext.save()
                await refreshService.refresh(feed: feed, context: modelContext)
                onAdded()
                dismiss()
            } catch {
                errorMessage = "Could not load feed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
