import SwiftUI
import SwiftData

@main
struct FableFluxApp: App {
    let modelContainer: ModelContainer

    init() {
        ClaudeKeyMigration.migrateIfNeeded()
        // Verhuist een bestaande store naar de App Group vóór de container 'm opent, zodat
        // de Share Extension (#201) meteen bij dezelfde data kan en niemand data verliest.
        SharedStoreMigration.migrateIfNeeded()
        do {
            modelContainer = try SharedModelContainer.make()
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
