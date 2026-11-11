//
//  PodcastAudioTests.swift
//  FableFluxTests
//

import SwiftData
import XCTest

@testable import FableFlux

/// Podcasts offline en op de achtergrond (#233): bestandsnamen, opruimregels, de keuze van
/// automatische downloads, hervatten, en een echte afspeelronde met AVPlayer op een lokaal
/// bestand.
@MainActor
final class PodcastAudioTests: XCTestCase {

    private var container: ModelContainer!
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)
    private let uur: TimeInterval = 3600

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Feed.self, FeedItem.self, FeedFolder.self, Topic.self,
            TopicSummary.self, FactCheckResult.self, MastodonAccount.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDownWithError() throws {
        AudioPlaybackService.shared.stop()
        PodcastDownloadService.shared.deleteAll()
        container = nil
    }

    // MARK: - Bestandsnamen

    func testExtensieKomtUitMimeTypeEnAndersUitDeURL() {
        XCTAssertEqual(PodcastDownloadStore.fileExtension(mimeType: "audio/mpeg", remoteURL: nil), "mp3")
        XCTAssertEqual(PodcastDownloadStore.fileExtension(mimeType: "audio/x-m4a", remoteURL: nil), "m4a")
        XCTAssertEqual(PodcastDownloadStore.fileExtension(mimeType: "audio/mp4; codecs=mp4a", remoteURL: nil), "m4a")
        // Onbekend type: de extensie van het pad, als AVFoundation die kent.
        XCTAssertEqual(
            PodcastDownloadStore.fileExtension(
                mimeType: "audio/unknown", remoteURL: URL(string: "https://x.nl/afl.m4a?t=1")), "m4a")
        // Tracking-redirect zonder extensie: veilige standaard.
        XCTAssertEqual(
            PodcastDownloadStore.fileExtension(
                mimeType: nil, remoteURL: URL(string: "https://dts.podtrac.com/redirect")),
            "mp3")
    }

    func testBestandsnaamGeeftHetItemIdTerug() {
        let id = UUID()
        let naam = PodcastDownloadStore.fileName(for: id, extension: "mp3")
        XCTAssertEqual(PodcastDownloadStore.itemID(fromFileName: naam), id)
        XCTAssertNil(PodcastDownloadStore.itemID(fromFileName: ".DS_Store"))
    }

    // MARK: - Opruimen

    func testOpruimenVolgtBewaarperiodeEnEenDagNaUitluisteren() {
        let weg = UUID()  // aflevering bestaat niet meer: opgeruimd door de bewaarperiode
        let langGeleden = UUID()  // 25 uur geleden uitgeluisterd
        let netKlaar = UUID()  // 2 uur geleden uitgeluisterd
        let bezig = UUID()  // nog niet uitgeluisterd
        let speeltNu = UUID()  // uitgeluisterd, maar nu weer aan het spelen

        let teVerwijderen = PodcastDownloadStore.filesToRemove(
            downloaded: [weg, langGeleden, netKlaar, bezig, speeltNu],
            episodes: [
                .init(id: langGeleden, finishedAt: nu.addingTimeInterval(-25 * uur)),
                .init(id: netKlaar, finishedAt: nu.addingTimeInterval(-2 * uur)),
                .init(id: bezig, finishedAt: nil),
                .init(id: speeltNu, finishedAt: nu.addingTimeInterval(-48 * uur)),
            ],
            protected: speeltNu,
            now: nu
        )
        XCTAssertEqual(teVerwijderen, [weg, langGeleden])
    }

    // MARK: - Automatisch downloaden

    func testAutomatischDeDrieNieuwsteNietUitgeluisterde() {
        let dagen = (0..<5).map { nu.addingTimeInterval(Double(-$0) * 24 * uur) }
        let ids = (0..<5).map { _ in UUID() }
        let kandidaten = [
            PodcastDownloadStore.AutoDownloadCandidate(id: ids[0], date: dagen[0], isFinished: true, wasQueued: false),
            .init(id: ids[1], date: dagen[1], isFinished: false, wasQueued: false),
            .init(id: ids[2], date: dagen[2], isFinished: false, wasQueued: false),
            .init(id: ids[3], date: dagen[3], isFinished: false, wasQueued: false),
            .init(id: ids[4], date: dagen[4], isFinished: false, wasQueued: false),
        ].shuffled()

        XCTAssertEqual(PodcastDownloadStore.autoDownloadSelection(kandidaten, limit: 3), [ids[1], ids[2], ids[3]])
    }

    func testEenEerderGedownloadeAfleveringKomtNietTerugEnVultHetVensterNietAan() {
        let nieuw = UUID()
        let alGehad = UUID()
        let oud = UUID()
        let kandidaten: [PodcastDownloadStore.AutoDownloadCandidate] = [
            .init(id: nieuw, date: nu, isFinished: false, wasQueued: false),
            .init(id: alGehad, date: nu.addingTimeInterval(-uur), isFinished: false, wasQueued: true),
            .init(id: oud, date: nu.addingTimeInterval(-2 * uur), isFinished: false, wasQueued: false),
        ]
        // Venster van 2: `alGehad` hoort bij de nieuwste twee, dus `oud` schuift niet op.
        XCTAssertEqual(PodcastDownloadStore.autoDownloadSelection(kandidaten, limit: 2), [nieuw])
    }

    // MARK: - Hervatten en weergave

    func testHervatpositie() {
        XCTAssertEqual(PodcastDownloadStore.resumePosition(saved: nil, duration: 600), 0)
        XCTAssertEqual(PodcastDownloadStore.resumePosition(saved: 3, duration: 600), 0, "net begonnen")
        XCTAssertEqual(PodcastDownloadStore.resumePosition(saved: 312, duration: 600), 312)
        XCTAssertEqual(PodcastDownloadStore.resumePosition(saved: 595, duration: 600), 0, "praktisch uit")
        XCTAssertEqual(PodcastDownloadStore.resumePosition(saved: 312, duration: nil), 312)
    }

    func testTijdEnSnelheidOpmaak() {
        XCTAssertEqual(PodcastDownloadStore.formatTime(75), "1:15")
        XCTAssertEqual(PodcastDownloadStore.formatTime(3725), "1:02:05")
        XCTAssertEqual(PodcastDownloadStore.formatTime(.nan), "0:00")
        XCTAssertEqual(PodcastPlayerView.rateLabel(1.5), "1,5×")
        XCTAssertEqual(PodcastPlayerView.rateLabel(2), "2×")
    }

    // MARK: - Onderhoud met echte opslag

    func testOnderhoudRuimtBestandenOpEnZetNieuweAfleveringenInDeWachtrij() throws {
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.invalid/podcast.xml", title: "Testpodcast")
        feed.autoDownloadEpisodes = true
        context.insert(feed)

        func aflevering(_ titel: String, uurGeleden: Double) -> FeedItem {
            let item = FeedItem(
                title: titel, pubDate: nu.addingTimeInterval(-uurGeleden * uur),
                enclosureURL: "https://example.invalid/\(titel).mp3", enclosureMIMEType: "audio/mpeg")
            item.feed = feed
            feed.items.append(item)
            context.insert(item)
            return item
        }
        let uitgeluisterd = aflevering("uitgeluisterd", uurGeleden: 1)
        uitgeluisterd.audioFinishedAt = nu.addingTimeInterval(-30 * uur)
        let a = aflevering("a", uurGeleden: 2)
        let b = aflevering("b", uurGeleden: 3)
        let c = aflevering("c", uurGeleden: 4)
        let d = aflevering("d", uurGeleden: 5)
        try context.save()

        // Bestanden: één van de uitgeluisterde aflevering, één van een al opgeruimde.
        let dir = try PodcastDownloadStore.directory()
        let verweesd = UUID()
        for id in [uitgeluisterd.id, verweesd] {
            let url = dir.appendingPathComponent(PodcastDownloadStore.fileName(for: id, extension: "mp3"))
            try Data([1, 2, 3]).write(to: url)
        }

        let service = PodcastDownloadService.shared
        service.performMaintenance(context: context, now: nu)

        let opSchijf = Set(PodcastDownloadStore.downloadedFiles(in: dir).keys)
        XCTAssertFalse(opSchijf.contains(uitgeluisterd.id), "30 uur na uitluisteren hoort het bestand weg")
        XCTAssertFalse(opSchijf.contains(verweesd), "zonder aflevering hoort het bestand weg")

        XCTAssertNotNil(a.autoDownloadQueuedAt)
        XCTAssertNotNil(b.autoDownloadQueuedAt)
        XCTAssertNotNil(c.autoDownloadQueuedAt)
        XCTAssertNil(d.autoDownloadQueuedAt, "alleen de drie nieuwste")
        XCTAssertNil(uitgeluisterd.autoDownloadQueuedAt)
        for item in [a, b, c] {
            guard case .downloading = service.state(for: item.id) else {
                return XCTFail("\(item.title) staat niet in de downloadwachtrij")
            }
        }
        XCTAssertEqual(service.state(for: d.id), .notDownloaded)
    }

    // MARK: - Echte afspeelronde

    /// Speelt een lokaal (gedownload) bestand van 2 s met AVPlayer af tot het einde: de
    /// speler moet het lokale bestand nemen, de duur leren, en na afloop de aflevering als
    /// uitgeluisterd markeren en de mini-speler sluiten.
    func testLokaalBestandSpeeltAfTotHetEindeEnMarkeertUitgeluisterd() throws {
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.invalid/podcast.xml", title: "Testpodcast")
        context.insert(feed)
        let item = FeedItem(
            title: "Korte aflevering", enclosureURL: "https://example.invalid/kort.wav", enclosureMIMEType: "audio/wav")
        item.feed = feed
        feed.items.append(item)
        context.insert(item)
        try context.save()

        let dir = try PodcastDownloadStore.directory()
        try Self.silentWAV(seconds: 2).write(
            to: dir.appendingPathComponent(PodcastDownloadStore.fileName(for: item.id, extension: "wav")))
        PodcastDownloadService.shared.refreshDownloadedFromDisk()
        XCTAssertNotNil(PodcastDownloadService.shared.localFileURL(for: item.id))

        let playback = AudioPlaybackService.shared
        playback.attach(context: context)
        playback.play(item)
        XCTAssertEqual(playback.current?.id, item.id)

        let einde = expectation(description: "aflevering uitgeluisterd")
        var duur: Double = 0
        func poll() {
            if playback.duration > 0 { duur = playback.duration }
            if playback.current == nil {
                einde.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
            }
        }
        poll()
        wait(for: [einde], timeout: 15)

        XCTAssertEqual(duur, 2, accuracy: 0.2, "duur van het lokale bestand")
        XCTAssertNotNil(item.audioFinishedAt)
        XCTAssertNil(item.playbackPosition, "een uitgeluisterde aflevering begint weer vooraan")
        XCTAssertTrue(item.isRead)
        XCTAssertFalse(playback.showsMiniPlayer)
    }

    /// Snelheid wijzigen tijdens pauze mag het afspelen niet starten: `AVPlayer.rate` zetten
    /// op een gepauzeerde speler speelt meteen af.
    func testSnelheidWijzigenTijdensPauzeStartHetAfspelenNiet() throws {
        let context = ModelContext(container)
        let item = FeedItem(
            title: "Pauze", enclosureURL: "https://example.invalid/pauze.wav", enclosureMIMEType: "audio/wav")
        context.insert(item)
        try context.save()
        let dir = try PodcastDownloadStore.directory()
        try Self.silentWAV(seconds: 30).write(
            to: dir.appendingPathComponent(PodcastDownloadStore.fileName(for: item.id, extension: "wav")))
        PodcastDownloadService.shared.refreshDownloadedFromDisk()

        let playback = AudioPlaybackService.shared
        let oudeSnelheid = playback.rate
        defer { playback.setRate(oudeSnelheid) }
        playback.attach(context: context)
        playback.play(item)
        let klaar = expectation(description: "speelt")
        func poll() {
            if playback.duration > 0, playback.isPlaying, playback.currentTime > 0.4 {
                klaar.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
            }
        }
        poll()
        wait(for: [klaar], timeout: 10)

        playback.pause()
        playback.setRate(1.5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.rate, 1.5)
        XCTAssertGreaterThan(item.playbackPosition ?? 0, 0, "pauze bewaart de positie")
    }

    /// Mono 8 kHz 16-bit stilte als WAV.
    private static func silentWAV(seconds: Int) -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(seconds) * sampleRate * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)  // byte rate
        append(UInt16(2))  // block align
        append(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
