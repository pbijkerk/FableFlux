import Foundation
import Security
import OSLog

/// Eenvoudige Keychain-wrapper voor het veilig opslaan van gevoelige strings.
enum KeychainService {

    /// Bewust de oude naam: een andere service maakt de opgeslagen sleutels onvindbaar (#145).
    private static let service = "com.rssreader.app"

    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: "keychain"
    )

    // MARK: - Opslaan

    /// Schrijft de waarde zonder de bestaande eerst te verwijderen: eerst bijwerken, en
    /// alleen als er nog geen item is toevoegen. Mislukt de write, dan blijft de oude
    /// waarde staan (#124). Eerder was het verwijderen-dan-toevoegen, waardoor een
    /// mislukte `SecItemAdd` de sleutel kwijtmaakte.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query = baseQuery(forKey: key)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData] = data
            status = SecItemAdd(attributes as CFDictionary, nil)
        }

        if status != errSecSuccess {
            logger.error("Keychain save failed for key '\(key)': OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    // MARK: - Ophalen

    /// Uitkomst van een leesactie. Onderscheidt "er is geen item" van "lezen mislukte",
    /// zodat de opstartmigratie een onleesbare Keychain niet voor een lege aanziet.
    enum LoadResult: Equatable {
        case found(String)
        case notFound
        case failed(OSStatus)
    }

    static func load(forKey key: String) -> String? {
        if case .found(let string) = loadResult(forKey: key) { return string }
        return nil
    }

    static func loadResult(forKey key: String) -> LoadResult {
        var query = baseQuery(forKey: key)
        query[kSecReturnData] = kCFBooleanTrue as Any
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
                logger.error("Keychain load succeeded but data is unreadable for key '\(key)'")
                return .failed(errSecDecode)
            }
            return .found(string)
        case errSecItemNotFound:
            return .notFound
        default:
            logger.error("Keychain load failed for key '\(key)': OSStatus \(status)")
            return .failed(status)
        }
    }

    // MARK: - Verwijderen

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for key '\(key)': OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    // MARK: - Hulpfuncties

    private static func baseQuery(forKey key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
    }
}
