import Foundation
import Observation
import OSLog
import SwiftData

/// Status van de download van één aflevering, voor de UI.
enum PodcastDownloadState: Equatable {
    case notDownloaded
    /// In de wachtrij of aan het downloaden; `progress` is `nil` zolang de grootte onbekend is
    /// (bijv. wachtend op wifi).
    case downloading(progress: Double?)
    case downloaded
    case failed(String)
}

/// Downloadt podcastafleveringen via een achtergrond-`URLSession` (#233).
///
/// Een achtergrondsessie laat iOS het downloaden overnemen: het gaat door als de app naar
/// de achtergrond gaat of door het systeem wordt afgesloten. Bij voltooiing start iOS de
/// app op de achtergrond en meldt dat via `handleEventsForBackgroundURLSession`
/// (`AppDelegate`). Wifi-only loopt via `URLRequest.allowsCellularAccess`: de taak wacht dan
/// vanzelf tot er wifi is.
@MainActor
@Observable
final class PodcastDownloadService {
    static let shared = PodcastDownloadService()

    /// Item-id's waarvan een bestand op schijf staat.
    private(set) var downloaded: Set<UUID> = []
    /// Lopende downloads met voortgang (0…1, of `nil` als de grootte nog onbekend is).
    private(set) var active: [UUID: Double?] = [:]
    private(set) var failures: [UUID: String] = [:]

    @ObservationIgnored private var tasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var backgroundCompletionHandler: (() -> Void)?
    @ObservationIgnored private var restored = false

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: AppConfiguration.Podcast.backgroundSessionIdentifier)
        // Door de gebruiker gevraagd: niet uitstellen tot iOS het "gunstig" vindt.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        // Mobiele data wordt per verzoek geregeld; de sessie zelf mag het, anders kan
        // de instelling "via mobiele data" nooit werken.
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    @ObservationIgnored private let delegate = PodcastDownloadDelegate()

    nonisolated private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.audio
    )

    private init() {
        delegate.service = self
    }

    // MARK: - Opstarten

    /// Leest de bestanden op schijf en koppelt lopende achtergrondtaken terug. Aanroepen bij
    /// het starten van de app; maakt daarmee ook de sessie aan, zodat iOS voltooide taken
    /// kan afleveren.
    func restore() {
        refreshDownloadedFromDisk()
        guard !restored else { return }
        restored = true
        session.getAllTasks { tasks in
            let pairs: [(UUID, URLSessionDownloadTask)] = tasks.compactMap { task in
                guard let download = task as? URLSessionDownloadTask,
                    let info = PodcastDownloadDelegate.TaskInfo(description: task.taskDescription),
                    task.state == .running || task.state == .suspended
                else { return nil }
                return (info.id, download)
            }
            Task { @MainActor in
                for (id, task) in pairs {
                    self.tasks[id] = task
                    self.active[id] = .some(Self.progress(of: task))
                }
            }
        }
    }

    func refreshDownloadedFromDisk() {
        guard let dir = try? PodcastDownloadStore.directory() else { return }
        downloaded = Set(PodcastDownloadStore.downloadedFiles(in: dir).keys)
    }

    /// Bewaart de completion handler van iOS; die moet worden aangeroepen zodra alle
    /// gebeurtenissen van de sessie zijn verwerkt (`urlSessionDidFinishEvents`).
    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == AppConfiguration.Podcast.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        backgroundCompletionHandler = completionHandler
        _ = session  // de sessie opnieuw aanmaken koppelt de delegate aan de wachtende gebeurtenissen
    }

    // MARK: - Status

    func state(for id: UUID) -> PodcastDownloadState {
        if downloaded.contains(id) { return .downloaded }
        if let progress = active[id] { return .downloading(progress: progress) }
        if let failure = failures[id] { return .failed(failure) }
        return .notDownloaded
    }

    /// Het lokale bestand van een aflevering, als die gedownload is.
    func localFileURL(for id: UUID) -> URL? {
        guard downloaded.contains(id), let dir = try? PodcastDownloadStore.directory() else { return nil }
        return PodcastDownloadStore.downloadedFiles(in: dir)[id]
    }

    // MARK: - Acties

    func download(_ item: FeedItem) {
        let id = item.id
        guard let remote = item.directAudioURL, !downloaded.contains(id), tasks[id] == nil else { return }
        var request = URLRequest(url: remote)
        request.allowsCellularAccess = UserDefaults.standard.bool(
            forKey: AppConfiguration.UserDefaultsKeys.podcastAllowsCellular)
        let task = session.downloadTask(with: request)
        let ext = PodcastDownloadStore.fileExtension(mimeType: item.enclosureMIMEType, remoteURL: remote)
        task.taskDescription = PodcastDownloadDelegate.TaskInfo(id: id, fileExtension: ext).description
        tasks[id] = task
        active[id] = .some(nil)
        failures[id] = nil
        task.resume()
        Self.logger.info("Download gestart: \(item.title, privacy: .public)")
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        active[id] = nil
    }

    func delete(_ id: UUID) {
        cancel(id)
        failures[id] = nil
        guard let url = localFileURL(for: id) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Verwijderen download mislukt: \(error.localizedDescription, privacy: .public)")
        }
        downloaded.remove(id)
    }

    func deleteAll() {
        for id in Array(tasks.keys) { cancel(id) }
        for id in downloaded { delete(id) }
        refreshDownloadedFromDisk()
    }

    // MARK: - Onderhoud na een verversing

    /// Ruimt downloads op die weg mogen en zet nieuwe afleveringen van feeds met
    /// automatisch downloaden in de wachtrij. Aanroepen na een verversing en bij het
    /// openen van de app.
    func performMaintenance(context: ModelContext, now: Date = Date()) {
        refreshDownloadedFromDisk()
        cleanUp(context: context, now: now)
        queueAutomaticDownloads(context: context, now: now)
    }

    private func cleanUp(context: ModelContext, now: Date) {
        guard !downloaded.isEmpty else { return }
        let ids = Array(downloaded)
        let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { ids.contains($0.id) })
        let items: [FeedItem]
        do {
            items = try context.fetch(descriptor)
        } catch {
            // Liever niets opruimen dan op basis van een mislukte fetch alles weggooien.
            Self.logger.error("Fetch voor opruimen downloads mislukt: \(error.localizedDescription, privacy: .public)")
            return
        }
        let remove = PodcastDownloadStore.filesToRemove(
            downloaded: downloaded,
            episodes: items.map { .init(id: $0.id, finishedAt: $0.audioFinishedAt) },
            protected: AudioPlaybackService.shared.current?.id,
            now: now
        )
        for id in remove { delete(id) }
        if !remove.isEmpty { Self.logger.info("\(remove.count) download(s) opgeruimd") }
    }

    private func queueAutomaticDownloads(context: ModelContext, now: Date) {
        let feeds =
            (try? context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.autoDownloadEpisodes == true })))
            ?? []
        var queuedAny = false
        for feed in feeds {
            let feedID = feed.id
            let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.feed?.id == feedID })
            let episodes = ((try? context.fetch(descriptor)) ?? []).filter(\.isAudioItem)
            let candidates = episodes.map {
                PodcastDownloadStore.AutoDownloadCandidate(
                    id: $0.id, date: $0.effectiveDate, isFinished: $0.audioFinishedAt != nil,
                    wasQueued: $0.autoDownloadQueuedAt != nil)
            }
            let selected = Set(PodcastDownloadStore.autoDownloadSelection(candidates))
            for episode in episodes where selected.contains(episode.id) {
                episode.autoDownloadQueuedAt = now
                download(episode)
                queuedAny = true
            }
        }
        if queuedAny { context.saveOrLog("de automatische podcastdownloads te bewaren") }
    }

    // MARK: - Terugmeldingen van de delegate

    fileprivate func didUpdate(id: UUID, progress: Double?) {
        guard tasks[id] != nil || active[id] != nil else { return }
        active[id] = .some(progress)
    }

    fileprivate func didFinish(id: UUID, error: String?) {
        tasks[id] = nil
        active[id] = nil
        if let error {
            failures[id] = error
            Self.logger.error("Download mislukt: \(error, privacy: .public)")
        } else {
            failures[id] = nil
            downloaded.insert(id)
        }
    }

    fileprivate func didFinishBackgroundEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    nonisolated private static func progress(of task: URLSessionTask) -> Double? {
        let expected = task.countOfBytesExpectedToReceive
        guard expected > 0 else { return nil }
        return Double(task.countOfBytesReceived) / Double(expected)
    }
}

// MARK: - Delegate

/// Losse delegate: de callbacks komen op een achtergrondqueue binnen. Het bestand moet
/// binnen `didFinishDownloadingTo` worden verplaatst (daarna gooit iOS het weg); de status
/// gaat daarna naar de MainActor.
private final class PodcastDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var service: PodcastDownloadService?

    /// Item-id en extensie, meegegeven als `taskDescription`; die overleeft een herstart van
    /// de app, een gewone property op de service niet.
    struct TaskInfo {
        let id: UUID
        let fileExtension: String

        init(id: UUID, fileExtension: String) {
            self.id = id
            self.fileExtension = fileExtension
        }

        init?(description: String?) {
            guard let parts = description?.split(separator: "|"), parts.count == 2,
                let id = UUID(uuidString: String(parts[0]))
            else { return nil }
            self.id = id
            self.fileExtension = String(parts[1])
        }

        var description: String { "\(id.uuidString)|\(fileExtension)" }
    }

    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.audio
    )

    /// Fouten die bij `didFinishDownloadingTo` al zijn gemeld; `didCompleteWithError` komt
    /// daarna ook nog, zonder fout, en mag die melding niet overschrijven.
    private var reported = Set<Int>()
    private let lock = NSLock()

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let info = TaskInfo(description: downloadTask.taskDescription) else { return }
        let progress =
            totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        Task { @MainActor [weak service] in service?.didUpdate(id: info.id, progress: progress) }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let info = TaskInfo(description: downloadTask.taskDescription) else { return }
        let error = Self.moveIntoPlace(location, info: info, response: downloadTask.response)
        lock.withLock { _ = reported.insert(downloadTask.taskIdentifier) }
        Task { @MainActor [weak service] in service?.didFinish(id: info.id, error: error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let info = TaskInfo(description: task.taskDescription) else { return }
        let alreadyReported = lock.withLock { reported.remove(task.taskIdentifier) != nil }
        guard !alreadyReported else { return }
        // Zelf geannuleerd: `cancel(_:)` heeft de status al gewist, geen foutmelding tonen.
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        let message = error?.localizedDescription ?? "Download onvolledig"
        Task { @MainActor [weak service] in service?.didFinish(id: info.id, error: message) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak service] in service?.didFinishBackgroundEvents() }
    }

    /// Verplaatst het tijdelijke bestand naar de downloadmap. Geeft een foutmelding terug,
    /// of `nil` bij succes. Een HTTP-fout of een HTML-pagina (bijv. een verlopen link die
    /// op een foutpagina uitkomt) wordt geen "aflevering".
    private static func moveIntoPlace(_ location: URL, info: TaskInfo, response: URLResponse?) -> String? {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return "Server gaf status \(http.statusCode)"
        }
        if let mime = response?.mimeType?.lowercased(), mime.hasPrefix("text/") {
            return "Geen audiobestand ontvangen"
        }
        do {
            let dir = try PodcastDownloadStore.directory()
            let target = dir.appendingPathComponent(
                PodcastDownloadStore.fileName(for: info.id, extension: info.fileExtension))
            let fm = FileManager.default
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: location, to: target)
            return nil
        } catch {
            logger.error("Download verplaatsen mislukt: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
