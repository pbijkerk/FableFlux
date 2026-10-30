import Foundation
import OSLog

/// Verhuist de SwiftData-store eenmalig van de app-eigen Application Support-map naar de
/// App Group-container, zodat `FableFluxShareExtension` (#201) dezelfde data kan lezen en
/// schrijven. Draait vóór `SharedModelContainer.make()` en is idempotent: zodra er al een
/// store in de groep staat — ook een lege, pas aangemaakte — gebeurt er niets meer.
///
/// Zonder deze stap zou een bestaande installatie bij de eerste start na de update zijn
/// feeds en artikelen "verliezen": de app zou een nieuwe, lege store in de App Group
/// aanmaken terwijl de oude data nog in de app-eigen map staat.
enum SharedStoreMigration {
    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.persistence
    )

    static func migrateIfNeeded(
        storeName: String = SharedModelContainer.storeName,
        groupContainerURL: URL? = SharedModelContainer.groupContainerURL,
        fileManager: FileManager = .default
    ) {
        guard let groupURL = groupContainerURL else {
            logger.error("App Group container niet beschikbaar; store blijft app-lokaal")
            return
        }

        let destination = groupURL.appendingPathComponent(storeName)
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let source = supportDir.appendingPathComponent(storeName)
        guard fileManager.fileExists(atPath: source.path) else { return }

        // SQLite bestaat uit hoofdbestand + write-ahead-log + shared memory-bestand;
        // alle drie moeten mee, anders riskeert de store corruptie bij de eerste schrijf.
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            let to = URL(fileURLWithPath: destination.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            do {
                try fileManager.copyItem(at: from, to: to)
            } catch {
                logger.error(
                    "Migratie van \(from.lastPathComponent, privacy: .public) mislukt: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        logger.info("SwiftData-store gemigreerd naar de App Group-container")
    }
}
