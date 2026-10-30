import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// De UI die in de Share Sheet verschijnt. Haalt de gedeelde URL op uit de
/// `NSExtensionContext`, voegt hem direct toe via `FeedAddingService` (#201) — dezelfde
/// functie als `AddFeedView` — en sluit zichzelf, zonder tussenscherm te tonen.
struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?

    enum Status {
        case loading
        case success(title: String)
        case failure(message: String)
    }

    @State private var status: Status = .loading
    @State private var modelContainer: ModelContainer?

    var body: some View {
        VStack(spacing: 16) {
            switch status {
            case .loading:
                ProgressView("Feed controleren…")
            case .success(let title):
                Label("'\(title)' toegevoegd aan FableFlux", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Sluiten") { close() }
            }
        }
        .padding(32)
        .task {
            await addSharedFeed()
        }
    }

    private func addSharedFeed() async {
        guard let rawURL = await extractSharedURL() else {
            status = .failure(message: "Geen geldige link gevonden om toe te voegen.")
            return
        }

        do {
            let container = try SharedModelContainer.make()
            modelContainer = container
            let context = ModelContext(container)
            let feed = try await FeedAddingService.addFeed(from: rawURL, context: context)
            status = .success(title: feed.title)
            // Kort tonen wat er is gebeurd, dan vanzelf terug naar de browser.
            try? await Task.sleep(for: .seconds(1))
            close()
        } catch let error as FeedAddError {
            status = .failure(message: error.errorDescription ?? "Feed kon niet worden toegevoegd.")
        } catch {
            status = .failure(message: "Feed kon niet worden toegevoegd: \(error.localizedDescription)")
        }
    }

    /// Doorzoekt de `NSExtensionItem`s op een URL- of tekst-attachment. Safari en de meeste
    /// browsers leveren de gedeelde pagina als `public.url`; sommige leveren alleen platte
    /// tekst (bijv. bij "kopieer link" via een los deel-icoon).
    private func extractSharedURL() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                    let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
                {
                    return url.absoluteString
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                    let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                        as? String
                {
                    return text
                }
            }
        }
        return nil
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
