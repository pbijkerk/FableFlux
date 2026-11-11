import Foundation

/// Bestandsbeheer voor gedownloade podcastafleveringen (#233): waar ze staan, hoe ze heten
/// en welke weg mogen. Bewust puur en `nonisolated` — geen SwiftData, geen netwerk — zodat
/// de regels los te toetsen zijn en de downloaddelegate er off-main bij kan.
///
/// Elke aflevering is één bestand `<FeedItem.id>.<extensie>` in Application Support. Het
/// bestand zelf is de waarheid over "gedownload": er staat niets dubbel in de database dat
/// uit de pas kan lopen als iOS de app tijdens een achtergronddownload afsluit.
enum PodcastDownloadStore {

    /// Application Support/Podcasts. Niet in Caches (dat mag iOS leeggooien, en dan is de
    /// aflevering offline ineens weg) en uitgesloten van de iCloud-backup: het zijn
    /// opnieuw te downloaden bestanden van vaak honderd MB of meer.
    static func directory(fileManager: FileManager = .default) throws -> URL {
        var dir = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Podcasts", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        }
        return dir
    }

    /// De extensie waarmee AVFoundation het lokale bestand herkent. Een bestand zonder
    /// (juiste) extensie speelt AVPlayer niet af, en podcast-URL's eindigen vaak op een
    /// tracking-redirect zonder extensie. Daarom eerst het MIME-type uit de feed.
    static func fileExtension(mimeType: String?, remoteURL: URL?) -> String {
        switch mimeType?.lowercased().split(separator: ";").first.map(String.init) {
        case "audio/mpeg", "audio/mp3", "audio/mpeg3", "audio/x-mpeg": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/x-aac": return "m4a"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        default: break
        }
        let ext = remoteURL?.pathExtension.lowercased() ?? ""
        let known = ["mp3", "m4a", "aac", "mp4", "wav", "aiff", "caf"]
        return known.contains(ext) ? ext : "mp3"
    }

    static func fileName(for id: UUID, extension ext: String) -> String {
        "\(id.uuidString).\(ext)"
    }

    /// Haalt het item-id uit een bestandsnaam; `nil` voor iets dat niet van ons is.
    static func itemID(fromFileName name: String) -> UUID? {
        let base = (name as NSString).deletingPathExtension
        return UUID(uuidString: base)
    }

    /// Alle gedownloade afleveringen in `dir`, per item-id.
    static func downloadedFiles(in dir: URL, fileManager: FileManager = .default) -> [UUID: URL] {
        let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var result: [UUID: URL] = [:]
        for url in urls {
            if let id = itemID(fromFileName: url.lastPathComponent) { result[id] = url }
        }
        return result
    }

    /// Wat er van één gedownloade aflevering in de database staat; genoeg om te beslissen
    /// of het bestand weg mag.
    struct EpisodeSnapshot: Equatable {
        let id: UUID
        let finishedAt: Date?
    }

    /// Welke bestanden weg mogen. Een bestand gaat weg als:
    /// - de aflevering niet meer bestaat: de bewaarperiode heeft hem opgeruimd, of de feed
    ///   is verwijderd. Zo gaat de download "mee met de bewaarperiode";
    /// - de aflevering langer dan `keepAfterFinished` geleden is uitgeluisterd.
    /// De aflevering die nu speelt (`protected`) blijft altijd staan.
    static func filesToRemove(
        downloaded: Set<UUID>,
        episodes: [EpisodeSnapshot],
        protected: UUID?,
        now: Date = Date(),
        keepAfterFinished: TimeInterval = AppConfiguration.Podcast.keepAfterFinished
    ) -> Set<UUID> {
        let byID = Dictionary(episodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return downloaded.filter { id in
            guard id != protected else { return false }
            guard let episode = byID[id] else { return true }
            guard let finished = episode.finishedAt else { return false }
            return now.timeIntervalSince(finished) >= keepAfterFinished
        }
    }

    /// Kandidaat voor automatisch downloaden.
    struct AutoDownloadCandidate: Equatable {
        let id: UUID
        let date: Date?
        let isFinished: Bool
        /// Al eens automatisch in de wachtrij gezet; dan niet opnieuw (ook niet als je de
        /// download zelf hebt verwijderd).
        let wasQueued: Bool
    }

    /// De nieuwste `limit` afleveringen die je nog niet hebt uitgeluisterd, voor zover ze
    /// nog niet eerder automatisch zijn gedownload. Afleveringen zonder datum sorteren
    /// achteraan: liever iets wat zeker nieuw is.
    static func autoDownloadSelection(
        _ candidates: [AutoDownloadCandidate], limit: Int = AppConfiguration.Podcast.autoDownloadCount
    ) -> [UUID] {
        candidates
            .filter { !$0.isFinished }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(limit)
            .filter { !$0.wasQueued }
            .map(\.id)
    }

    /// De positie waarop een aflevering moet beginnen: de bewaarde positie, tenzij die zo
    /// vroeg is dat je net was begonnen, of zo laat dat er niets meer te horen valt.
    static func resumePosition(saved: Double?, duration: Double?) -> Double {
        guard let saved, saved.isFinite, saved >= AppConfiguration.Podcast.minimumResumePosition else { return 0 }
        if let duration, duration.isFinite, duration > 0,
            saved >= duration - AppConfiguration.Podcast.finishedMargin
        {
            return 0
        }
        return saved
    }

    /// Tijd als `m:ss` of `u:mm:ss`.
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Bestandsgrootte van alle downloads samen, voor Instellingen.
    static func totalSize(in dir: URL, fileManager: FileManager = .default) -> Int64 {
        downloadedFiles(in: dir, fileManager: fileManager).values.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }
}
