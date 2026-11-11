import AVFoundation
import MediaPlayer
import Observation
import OSLog
import SwiftData
import UIKit

/// Wat de speler van de huidige aflevering vasthoudt. Een kopie, geen `FeedItem`: de
/// bewaarperiode kan de aflevering tijdens het luisteren in een achtergrondcontext
/// verwijderen, en een verwijderd model aanraken laat de app crashen.
struct NowPlayingEpisode: Equatable {
    let id: UUID
    let title: String
    let sourceTitle: String
    let artworkURL: URL?
}

/// De ene podcastspeler van de app (#233).
///
/// Leeft los van de schermen, zodat de aflevering doorspeelt als je het afleveringsscherm
/// verlaat of het scherm vergrendelt (dat laatste vraagt ook `UIBackgroundModes: audio`).
/// Alles via Apple-frameworks: `AVPlayer` en `AVAudioSession` voor het afspelen,
/// `MPNowPlayingInfoCenter` en `MPRemoteCommandCenter` voor vergrendelscherm, Control
/// Center, oortjes, CarPlay en de Apple Watch.
@MainActor
@Observable
final class AudioPlaybackService {
    static let shared = AudioPlaybackService()

    private(set) var current: NowPlayingEpisode?
    /// Speelt (of wil spelen en buffert); de knop toont dan "pauze".
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var rate: Float
    private(set) var lastError: String?
    /// Het item waarvan het afleveringsscherm nu open is; de mini-speler verbergt zich dan
    /// voor die aflevering, die heeft daar al een volle speler.
    var visibleDetailItemID: UUID?

    var showsMiniPlayer: Bool {
        guard let current else { return false }
        return current.id != visibleDetailItemID
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastPositionSave = Date.distantPast
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var modelContext: ModelContext?
    /// Was de aflevering aan het spelen toen een onderbreking (telefoon, Siri) begon?
    @ObservationIgnored private var wasPlayingBeforeInterruption = false

    nonisolated private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.audio
    )

    private init() {
        let stored = UserDefaults.standard.float(forKey: AppConfiguration.UserDefaultsKeys.podcastPlaybackRate)
        rate = AppConfiguration.Podcast.playbackRates.contains(stored) ? stored : 1.0
        player.defaultRate = rate
        observePlayer()
        observeAudioSession()
        configureRemoteCommands()
    }

    /// De context waarin de luisterpositie wordt bewaard. Eén keer zetten vanuit de app.
    func attach(context: ModelContext) {
        modelContext = context
    }

    // MARK: - Afspelen

    /// Speelt `item`, of hervat het als het al de huidige aflevering is. Een gedownload
    /// bestand gaat voor op streamen.
    func play(_ item: FeedItem) {
        if current?.id == item.id {
            resume()
            return
        }
        guard let remote = item.directAudioURL else { return }
        savePosition()

        let source = PodcastDownloadService.shared.localFileURL(for: item.id) ?? remote
        let episode = NowPlayingEpisode(
            id: item.id,
            title: item.title,
            sourceTitle: item.sourceTitle ?? "Podcast",
            artworkURL: item.imageURL.flatMap(URL.init(string:))
        )
        current = episode
        currentTime = 0
        duration = 0
        lastError = nil
        artwork = nil
        isBuffering = true

        let start = PodcastDownloadStore.resumePosition(saved: item.playbackPosition, duration: nil)
        pendingSeek = start > 0 ? start : nil
        currentTime = start

        let playerItem = AVPlayerItem(url: source)
        // Gesproken woord: houd de toonhoogte natuurlijk bij 1,5× of 2×.
        playerItem.audioTimePitchAlgorithm = .timeDomain
        observeStatus(of: playerItem)
        player.replaceCurrentItem(with: playerItem)

        activateSession()
        player.play()
        updateNowPlaying()
        loadArtwork(for: episode)
        Self.logger.info(
            "Afspelen: \(item.title, privacy: .public) (\(source.isFileURL ? "lokaal" : "stream", privacy: .public))")
    }

    func resume() {
        guard current != nil else { return }
        activateSession()
        player.play()
    }

    func pause() {
        player.pause()
        savePosition()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        let upper = duration > 0 ? duration : .greatestFiniteMagnitude
        let target = min(max(0, seconds), upper)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        player.defaultRate = newRate
        // De speler zelf vragen, niet `isPlaying`: die volgt via KVO en kan net achterlopen,
        // en `rate` zetten op een gepauzeerde speler start het afspelen.
        if player.rate != 0 { player.rate = newRate }
        UserDefaults.standard.set(newRate, forKey: AppConfiguration.UserDefaultsKeys.podcastPlaybackRate)
        updateNowPlaying()
    }

    /// Stopt en sluit de mini-speler. De positie blijft bewaard.
    func stop() {
        stop(savingPosition: true)
    }

    private func stop(savingPosition: Bool) {
        if savingPosition { savePosition() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        isBuffering = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        deactivateSession()
    }

    /// Bewaart de luisterpositie van de huidige aflevering. Ook aanroepen als de app naar
    /// de achtergrond gaat.
    func savePosition() {
        guard let current, currentTime > 0 else { return }
        guard let item = fetchItem(current.id) else { return }
        item.playbackPosition = currentTime
        lastPositionSave = Date()
        modelContext?.saveOrLog("de luisterpositie te bewaren")
    }

    // MARK: - Einde aflevering

    private func didPlayToEnd() {
        guard let current else { return }
        if let item = fetchItem(current.id) {
            item.playbackPosition = nil
            item.audioFinishedAt = Date()
            item.isRead = true
            modelContext?.saveOrLog("de uitgeluisterde aflevering te bewaren")
        }
        Self.logger.info("Uitgeluisterd: \(current.title, privacy: .public)")
        // Niet de eindpositie bewaren: een uitgeluisterde aflevering begint weer vooraan.
        stop(savingPosition: false)
    }

    private func fetchItem(_ id: UUID) -> FeedItem? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Audiosessie

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.longFormAudio`: iOS behandelt dit als podcast/audioboek en routeert via
            // AirPlay 2 zoals Apple Podcasts; `.spokenAudio` laat navigatie-aanwijzingen
            // de aflevering pauzeren in plaats van eroverheen te praten.
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            Self.logger.error("Audiosessie activeren mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo
                MainActor.assumeIsolated { self?.handleInterruption(info) }
            })
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo
                MainActor.assumeIsolated { self?.handleRouteChange(info) }
            })
        notificationTokens.append(
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] note in
                let item = note.object as? AVPlayerItem
                MainActor.assumeIsolated {
                    guard let self, item === self.player.currentItem else { return }
                    self.didPlayToEnd()
                }
            })
    }

    /// Telefoongesprek, Siri, wekker: iOS pauzeert de audio. Daarna hervatten als iOS dat
    /// aangeeft (`.shouldResume`) en de aflevering speelde.
    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            savePosition()
        case .ended:
            let optionsRaw = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), wasPlayingBeforeInterruption { resume() }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    /// Oortjes uit of bluetooth weg: pauzeren, anders schalt de aflevering ineens uit de
    /// luidspreker (Apple-richtlijn voor audio-apps).
    private func handleRouteChange(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        pause()
    }

    // MARK: - Speler observeren

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(status) }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            let message = item.error?.localizedDescription
            Task { @MainActor in self?.statusChanged(status, duration: seconds, error: message) }
        }
    }

    private func statusChanged(_ status: AVPlayerItem.Status, duration seconds: Double, error: String?) {
        switch status {
        case .readyToPlay:
            if seconds.isFinite, seconds > 0 { duration = seconds }
            if let pending = pendingSeek {
                pendingSeek = nil
                seek(to: PodcastDownloadStore.resumePosition(saved: pending, duration: duration))
            }
            updateNowPlaying()
        case .failed:
            lastError = error ?? "Aflevering kon niet worden afgespeeld"
            isBuffering = false
            Self.logger.error("Afspelen mislukt: \(self.lastError ?? "", privacy: .public)")
        default:
            break
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status != .paused
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard current != nil, pendingSeek == nil, seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds
        if duration == 0, let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
            updateNowPlaying()
        }
        if isPlaying, Date().timeIntervalSince(lastPositionSave) >= AppConfiguration.Podcast.positionSaveInterval {
            savePosition()
        }
    }

    // MARK: - Vergrendelscherm en Control Center

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.sourceTitle,
            MPMediaItemPropertyAlbumTitle: current.sourceTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            // De werkelijke snelheid (0 bij pauze): daarmee laat iOS de tijdbalk zelf lopen.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(for episode: NowPlayingEpisode) {
        guard let url = episode.artworkURL else { return }
        Task {
            guard let response = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: response.0),
                self.current?.id == episode.id
            else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    /// Buiten de MainActor: iOS roept het verzoek om de afbeelding op een eigen queue aan.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: AppConfiguration.Podcast.skipBackward)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -AppConfiguration.Podcast.skipBackward) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: AppConfiguration.Podcast.skipForward)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: AppConfiguration.Podcast.skipForward) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = AppConfiguration.Podcast.playbackRates.map {
            NSNumber(value: $0)
        }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let newRate = event.playbackRate
            MainActor.assumeIsolated { self?.setRate(newRate) }
            return .success
        }
        // Volgende/vorige track bestaan niet bij een losse aflevering; uitgeschakeld tonen
        // iOS en de oortjes de sprongknoppen in plaats daarvan.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }
}
