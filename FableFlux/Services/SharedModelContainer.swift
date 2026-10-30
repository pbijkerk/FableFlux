import Foundation
import SwiftData

/// Bouwt de SwiftData-`ModelContainer` die de hoofdapp en `FableFluxShareExtension` delen
/// (#201). Beide targets roepen dezelfde functie aan zodat het schema niet kan uiteenlopen,
/// en de store op dezelfde plek staat: in de App Group-container als die beschikbaar is,
/// anders (bijv. in een testomgeving zonder entitlements) lokaal in-app.
enum SharedModelContainer {

    /// Bestandsnaam van de SwiftData-store. Ongewijzigd ten opzichte van het oude,
    /// app-lokale pad, zodat `SharedStoreMigration` 'm kan herkennen en verplaatsen.
    static let storeName = "default.store"

    static let schema = Schema([
        Feed.self, FeedItem.self, Topic.self, TopicSummary.self, FeedFolder.self,
        MastodonAccount.self, FactCheckResult.self,
    ])

    /// De map waarin de gedeelde store hoort te staan, of `nil` als de App Group niet
    /// beschikbaar is (ontbrekende entitlement/provisioning).
    static var groupContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfiguration.AppGroup.identifier
        )
    }

    static func make() throws -> ModelContainer {
        let config: ModelConfiguration
        if let groupURL = groupContainerURL {
            let storeURL = groupURL.appendingPathComponent(storeName)
            config = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // Val terug op de standaardlocatie: de extensie kan hierdoor niet schrijven,
            // maar de hoofdapp blijft werken in plaats van te crashen.
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        return try ModelContainer(for: schema, configurations: config)
    }
}
