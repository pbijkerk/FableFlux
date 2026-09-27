//
//  ClaudeKeyMigrationTests.swift
//  FableFluxTests
//

import Security
import XCTest

@testable import FableFlux

/// Toetst de opstartmigratie van de Claude-sleutel en de atomaire Keychain-write (#124).
///
/// De migratie krijgt een nep-Keychain mee, zodat ook een mislukte write en een onleesbare
/// Keychain te toetsen zijn. De `save`-tests gebruiken de echte Keychain, met een eigen
/// account-naam per test, zodat een echte sleutel nooit wordt geraakt.
final class ClaudeKeyMigrationTests: XCTestCase {

    private let defaultsKey = "legacyKey"
    private let keychainKey = "claudeKey"
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var keychain: [String: String] = [:]
    private var saveSucceeds = true
    private var loadFailure: OSStatus?

    override func setUp() {
        super.setUp()
        suiteName = "ClaudeKeyMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        keychain = [:]
        saveSucceeds = true
        loadFailure = nil
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func migrate() -> ClaudeKeyMigration.Outcome {
        ClaudeKeyMigration.migrateIfNeeded(
            defaults: defaults,
            defaultsKey: defaultsKey,
            keychainKey: keychainKey,
            load: { key in
                if let status = self.loadFailure { return .failed(status) }
                return self.keychain[key].map { .found($0) } ?? .notFound
            },
            save: { value, key in
                guard self.saveSucceeds else { return false }
                self.keychain[key] = value
                return true
            }
        )
    }

    // MARK: - Migratie

    func testLegacySleutelWordtGemigreerd() {
        defaults.set("sk-oud", forKey: defaultsKey)

        XCTAssertEqual(migrate(), .migrated)
        XCTAssertEqual(keychain[keychainKey], "sk-oud")
        XCTAssertNil(defaults.string(forKey: defaultsKey))
    }

    func testTweemaalStartenIsIdempotent() {
        defaults.set("sk-oud", forKey: defaultsKey)

        XCTAssertEqual(migrate(), .migrated)
        XCTAssertEqual(migrate(), .notNeeded)
        XCTAssertEqual(keychain[keychainKey], "sk-oud")
        XCTAssertNil(defaults.string(forKey: defaultsKey))
    }

    func testBestaandeKeychainWaardeWordtNietOverschreven() {
        keychain[keychainKey] = "sk-nieuw"
        defaults.set("sk-oud", forKey: defaultsKey)

        XCTAssertEqual(migrate(), .notNeeded)
        XCTAssertEqual(keychain[keychainKey], "sk-nieuw")
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "sk-oud")
    }

    func testMislukteWriteLaatLegacySleutelStaan() {
        defaults.set("sk-oud", forKey: defaultsKey)
        saveSucceeds = false

        XCTAssertEqual(migrate(), .deferred)
        XCTAssertNil(keychain[keychainKey])
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "sk-oud")
    }

    func testOnleesbareKeychainStelMigratieUit() {
        defaults.set("sk-oud", forKey: defaultsKey)
        loadFailure = errSecInteractionNotAllowed

        XCTAssertEqual(migrate(), .deferred)
        XCTAssertNil(keychain[keychainKey])
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "sk-oud")
    }

    func testZonderLegacySleutelGebeurtNiets() {
        XCTAssertEqual(migrate(), .notNeeded)
        XCTAssertTrue(keychain.isEmpty)
    }

    // MARK: - Atomaire save (echte Keychain)

    func testSaveVoegtToeEnWerktBij() {
        let key = "test.r124.\(UUID().uuidString)"
        defer { KeychainService.delete(forKey: key) }

        XCTAssertEqual(KeychainService.loadResult(forKey: key), .notFound)
        XCTAssertTrue(KeychainService.save("eerste", forKey: key))
        XCTAssertEqual(KeychainService.loadResult(forKey: key), .found("eerste"))
        XCTAssertTrue(KeychainService.save("tweede", forKey: key))
        XCTAssertEqual(KeychainService.loadResult(forKey: key), .found("tweede"))
    }
}
