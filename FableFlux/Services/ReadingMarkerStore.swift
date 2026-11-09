import Foundation

/// "Hier was je gebleven" per lijst of map (#225, uit schets 2C).
///
/// Twee waarden per lijst:
/// - `pending`: het nieuwste artikel dat je deze sessie in die lijst hebt zien langskomen.
/// - `committed`: de markering die de lijst toont. Die schuift pas op als de app naar de
///   achtergrond gaat (`commitAll`), zodat de lijn niet onder je vandaan verspringt terwijl
///   je leest, en na een herstart nog klopt.
struct ReadingMarkerStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let standard = ReadingMarkerStore()

    private var committedKey: String { AppConfiguration.UserDefaultsKeys.readingMarkersCommitted }
    private var pendingKey: String { AppConfiguration.UserDefaultsKeys.readingMarkersPending }

    private func dictionary(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    /// De markering die de lijst nu toont, of `nil` als je deze lijst nog nooit hebt gezien.
    func marker(for scope: String) -> Date? {
        dictionary(committedKey)[scope].map(Date.init(timeIntervalSince1970:))
    }

    /// Een artikel kwam in beeld. Alleen een nieuwer artikel schuift `pending` op.
    func noteSeen(_ date: Date?, in scope: String) {
        guard let date else { return }
        var pending = dictionary(pendingKey)
        let value = date.timeIntervalSince1970
        guard value > (pending[scope] ?? -.infinity) else { return }
        pending[scope] = value
        defaults.set(pending, forKey: pendingKey)
    }

    /// Bij naar de achtergrond gaan: wat je hebt gezien, wordt de nieuwe markering.
    func commitAll() {
        let pending = dictionary(pendingKey)
        guard !pending.isEmpty else { return }
        var committed = dictionary(committedKey)
        for (scope, value) in pending where value > (committed[scope] ?? -.infinity) {
            committed[scope] = value
        }
        defaults.set(committed, forKey: committedKey)
    }

    // MARK: - Lijstsleutels

    static func allArticlesScope(folderID: UUID?) -> String {
        folderID.map { "folder:\($0.uuidString)" } ?? "all"
    }

    static func folderScope(_ id: UUID) -> String { "folder:\(id.uuidString)" }
    static func feedScope(_ id: UUID) -> String { "feed:\(id.uuidString)" }
}

/// Waar de lijn "Hier was je gebleven" in een lijst staat (#225).
enum ReadingMarker {
    /// De index van het eerste artikel dat niet nieuwer is dan de markering. `nil` als er
    /// geen markering is, als alles nieuw is of als er niets nieuws bovenaan staat: dan heeft
    /// een lijn geen betekenis. `items` staat op datum, nieuwste eerst.
    static func dividerIndex(dates: [Date?], marker: Date?) -> Int? {
        guard let marker, !dates.isEmpty else { return nil }
        guard let index = dates.firstIndex(where: { ($0 ?? .distantPast) <= marker }), index > 0 else {
            return nil
        }
        return index
    }
}
