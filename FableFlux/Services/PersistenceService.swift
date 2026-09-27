import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Eén logger voor alle SwiftData-opslagfouten, zodat ze in Console op één
/// categorie te filteren zijn (dezelfde opzet als `KeychainService`).
private let persistenceLogger = Logger(
    subsystem: AppConfiguration.LogSubsystem.main,
    category: AppConfiguration.LogSubsystem.Category.persistence
)

// MARK: - Opslaan

extension ModelContext {

    /// Slaat de wachtende wijzigingen op en logt de fout als dat mislukt.
    ///
    /// Vervangt het oude `try?`-patroon rond `save()`: dat gooide de fout weg, waardoor
    /// een mislukte opslag stil verdween. Gebruik deze variant voor impliciete
    /// wijzigingen (bijvoorbeeld een gelezen-markering); voor een expliciete
    /// gebruikersactie is `saveOrReport(_:melding:)` bedoeld.
    ///
    /// - Parameter handeling: wat er werd opgeslagen, als infinitief-zin
    ///   ("het artikel te bewaren"). Komt alleen in het log terecht.
    /// - Returns: `true` als het opslaan slaagde.
    @discardableResult
    func saveOrLog(_ handeling: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            persistenceLogger.error(
                "Opslaan mislukt bij poging om \(handeling, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Slaat op na een expliciete gebruikersactie: logt de fout én vult `melding`
    /// zodat het scherm kan tonen dat de wijziging niet bewaard is.
    ///
    /// - Parameters:
    ///   - handeling: wat de gebruiker probeerde, als infinitief-zin
    ///     ("het onderwerp te bewaren"). Wordt in de melding getoond.
    ///   - melding: de `@State` waarop het scherm `.opslagFoutmelding(_:)` heeft gezet.
    /// - Returns: `true` als het opslaan slaagde.
    @discardableResult
    func saveOrReport(_ handeling: String, melding: inout OpslagFoutmelding?) -> Bool {
        guard saveOrLog(handeling) else {
            melding = OpslagFoutmelding(handeling: handeling)
            return false
        }
        return true
    }
}

// MARK: - Melding

/// Een mislukte opslag van een expliciete gebruikersactie, klaar om te tonen.
struct OpslagFoutmelding: Identifiable {
    let id = UUID()

    /// Wat de gebruiker probeerde, als infinitief-zin ("het onderwerp te bewaren").
    let handeling: String

    var tekst: String {
        "Het is niet gelukt om \(handeling). Probeer het opnieuw."
    }
}

extension View {

    /// Toont een standaardmelding zodra een expliciete gebruikersactie niet kon
    /// worden opgeslagen. De melding wordt gevuld door `saveOrReport(_:melding:)`.
    func opslagFoutmelding(_ melding: Binding<OpslagFoutmelding?>) -> some View {
        alert(
            "Opslaan mislukt",
            isPresented: Binding(
                get: { melding.wrappedValue != nil },
                set: { if !$0 { melding.wrappedValue = nil } }
            ),
            presenting: melding.wrappedValue
        ) { _ in
            Button("Oké", role: .cancel) {}
        } message: { fout in
            Text(fout.tekst)
        }
    }
}
