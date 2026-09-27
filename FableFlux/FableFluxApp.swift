import SwiftUI
import SwiftData

@main
struct FableFluxApp: App {
    let modelContainer: ModelContainer

    init() {
        ClaudeKeyMigration.migrateIfNeeded()
        do {
            let schema = Schema([
                Feed.self, FeedItem.self, Topic.self, TopicSummary.self, FeedFolder.self, MastodonAccount.self,
                FactCheckResult.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
