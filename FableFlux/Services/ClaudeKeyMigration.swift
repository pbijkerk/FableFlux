import Foundation
import OSLog

/// Verhuist de Claude-sleutel eenmalig van `UserDefaults` naar de Keychain (#124).
///
/// Draait bij elke app-start en is idempotent: er wordt alleen gemigreerd als de Keychain
/// uitdrukkelijk géén item heeft en `UserDefaults` wél een sleutel. De oude waarde verdwijnt
/// pas nadat de nieuwe is teruggelezen. Lukt lezen of schrijven niet — bijvoorbeeld een
/// Keychain die vlak na het opstarten nog vergrendeld is — dan blijft alles staan en volgt
/// een nieuwe poging bij de volgende start.
///
/// De leesterugvallen op `UserDefaults` in `SettingsView` en `ContentView` blijven bewust
/// bestaan tot deze migratie op het toestel is geverifieerd.
enum ClaudeKeyMigration {

    enum Outcome: Equatable {
        case migrated
        case notNeeded
        case deferred
    }

    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: "keychain"
    )

    @discardableResult
    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        defaultsKey: String = AppConfiguration.UserDefaultsKeys.claudeAPIKey,
        keychainKey: String = AppConfiguration.KeychainKeys.claudeAPIKey,
        load: (String) -> KeychainService.LoadResult = KeychainService.loadResult(forKey:),
        save: (String, String) -> Bool = { KeychainService.save($0, forKey: $1) }
    ) -> Outcome {
        guard let legacy = defaults.string(forKey: defaultsKey), !legacy.isEmpty else {
            return .notNeeded
        }

        switch load(keychainKey) {
        case .found:
            return .notNeeded
        case .failed:
            logger.error("Claude key migration deferred: Keychain unreadable")
            return .deferred
        case .notFound:
            break
        }

        guard save(legacy, keychainKey), load(keychainKey) == .found(legacy) else {
            logger.error("Claude key migration deferred: Keychain write not confirmed")
            return .deferred
        }

        defaults.removeObject(forKey: defaultsKey)
        return .migrated
    }
}
