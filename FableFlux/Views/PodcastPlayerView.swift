import SwiftUI

// MARK: - Speler in het afleveringsscherm

/// De volle speler bovenaan een podcastaflevering (#233). Bedient de gedeelde
/// `AudioPlaybackService`; is deze aflevering (nog) niet de huidige, dan toont hij een
/// afspeelknop met de bewaarde positie. Bouwt zelf geen speler op: de artikelpager maakt
/// buurpagina's vooraf aan, en die mogen niets gaan laden of afspelen.
struct PodcastPlayerView: View {
    let item: FeedItem
    private var playback: AudioPlaybackService { .shared }

    /// Positie tijdens het slepen; pas bij loslaten wordt er gezocht.
    @State private var scrubPosition: Double?

    private var isCurrent: Bool { playback.current?.id == item.id }

    var body: some View {
        VStack(spacing: 10) {
            if isCurrent {
                activeControls
            } else {
                idleControls
            }
            if isCurrent, let error = playback.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: Aflevering speelt (of staat gepauzeerd klaar)

    private var activeControls: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubPosition ?? playback.currentTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(1, playback.duration),
                onEditingChanged: { editing in
                    guard !editing, let target = scrubPosition else { return }
                    playback.seek(to: target)
                    scrubPosition = nil
                }
            )
            .disabled(playback.duration == 0)
            .tint(.primary)
            .accessibilityLabel("Positie in aflevering")

            HStack {
                Text(PodcastDownloadStore.formatTime(scrubPosition ?? playback.currentTime))
                Spacer()
                Text(
                    playback.duration > 0
                        ? "-"
                            + PodcastDownloadStore.formatTime(
                                playback.duration - (scrubPosition ?? playback.currentTime))
                        : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack {
                rateMenu
                Spacer()
                skipButton(seconds: -AppConfiguration.Podcast.skipBackward, symbol: "gobackward.15")
                Spacer()
                Button {
                    playback.togglePlayPause()
                } label: {
                    ZStack {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                        if playback.isBuffering {
                            ProgressView().tint(.white)
                        }
                    }
                }
                .accessibilityLabel(playback.isPlaying ? "Pauzeer" : "Speel af")
                Spacer()
                skipButton(seconds: AppConfiguration.Podcast.skipForward, symbol: "goforward.30")
                Spacer()
                PodcastDownloadButton(item: item)
            }
            .foregroundStyle(.primary)
        }
    }

    private func skipButton(seconds: Double, symbol: String) -> some View {
        Button {
            playback.skip(by: seconds)
        } label: {
            Image(systemName: symbol).font(.title2)
        }
        .accessibilityLabel(seconds < 0 ? "\(Int(-seconds)) seconden terug" : "\(Int(seconds)) seconden vooruit")
    }

    private var rateMenu: some View {
        Menu {
            Picker("Afspeelsnelheid", selection: Binding(get: { playback.rate }, set: { playback.setRate($0) })) {
                ForEach(AppConfiguration.Podcast.playbackRates, id: \.self) { rate in
                    Text(Self.rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Text(Self.rateLabel(playback.rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Afspeelsnelheid \(Self.rateLabel(playback.rate))")
    }

    static func rateLabel(_ rate: Float) -> String {
        let formatted = rate == rate.rounded() ? String(format: "%.0f", rate) : String(format: "%.1f", rate)
        return formatted.replacingOccurrences(of: ".", with: ",") + "×"
    }

    // MARK: Aflevering speelt niet

    private var idleControls: some View {
        HStack(spacing: 14) {
            Button {
                playback.play(item)
            } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 52))
            }
            .accessibilityLabel(resumeLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(resumeLabel).font(.subheadline.weight(.semibold))
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PodcastDownloadButton(item: item)
        }
        .foregroundStyle(.primary)
    }

    private var resumeLabel: String {
        let position = PodcastDownloadStore.resumePosition(saved: item.playbackPosition, duration: nil)
        return position > 0 ? "Verder vanaf \(PodcastDownloadStore.formatTime(position))" : "Speel af"
    }

    private var statusLine: String {
        if item.audioFinishedAt != nil { return "Uitgeluisterd" }
        switch PodcastDownloadService.shared.state(for: item.id) {
        case .downloaded: return "Gedownload · speelt offline"
        case .downloading: return "Bezig met downloaden…"
        case .failed: return "Download mislukt · streamen kan wel"
        case .notDownloaded: return "Streamen"
        }
    }
}

// MARK: - Downloadknop

/// Download, voortgang (tik = annuleren) of gedownload (menu met verwijderen).
struct PodcastDownloadButton: View {
    let item: FeedItem
    private var downloads: PodcastDownloadService { .shared }

    var body: some View {
        switch downloads.state(for: item.id) {
        case .notDownloaded:
            Button {
                downloads.download(item)
            } label: {
                icon("arrow.down.circle")
            }
            .accessibilityLabel("Download aflevering")
        case .failed(let message):
            Button {
                downloads.download(item)
            } label: {
                icon("exclamationmark.arrow.circlepath")
            }
            .accessibilityLabel("Download opnieuw proberen")
            .accessibilityHint(message)
        case .downloading(let progress):
            Button {
                downloads.cancel(item.id)
            } label: {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                    if let progress {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: "stop.fill").font(.system(size: 9))
                }
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Download annuleren")
            .accessibilityValue(progress.map { "\(Int($0 * 100)) procent" } ?? "in wachtrij")
        case .downloaded:
            Menu {
                Button(role: .destructive) {
                    downloads.delete(item.id)
                } label: {
                    Label("Verwijder download", systemImage: "trash")
                }
            } label: {
                icon("checkmark.circle.fill")
            }
            .accessibilityLabel("Gedownload")
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .frame(width: 44, height: 44)
    }
}

// MARK: - Mini-speler

/// Mini-speler boven de tabbalk (#233): zichtbaar zolang er een aflevering geladen is en je
/// niet op het scherm van die aflevering zit. Tik opent de aflevering.
struct MiniPlayerView: View {
    var onOpen: () -> Void
    private var playback: AudioPlaybackService { .shared }

    var body: some View {
        if playback.showsMiniPlayer, let episode = playback.current {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: playback.isPlaying)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(episode.sourceTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(episode.title)")

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(playback.isPlaying ? "Pauzeer" : "Speel af")

                Button {
                    playback.skip(by: AppConfiguration.Podcast.skipForward)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("30 seconden vooruit")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: AppConfiguration.Podcast.miniPlayerHeight - 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottom) {
                // Voortgang als dunne lijn onderaan, zoals Apple Podcasts.
                GeometryReader { geo in
                    let fraction = playback.duration > 0 ? min(1, playback.currentTime / playback.duration) : 0
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * fraction, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 3)
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            .contextMenu {
                Button(role: .destructive) {
                    playback.stop()
                } label: {
                    Label("Stop afspelen", systemImage: "xmark")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Ruimte voor de mini-speler

private struct MiniPlayerInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra hoogte die de mini-speler boven de tabbalk inneemt; schermen met eigen
    /// knoppen onderin (de actiecapsule van het leesscherm) schuiven daarmee op.
    var miniPlayerInset: CGFloat {
        get { self[MiniPlayerInsetKey.self] }
        set { self[MiniPlayerInsetKey.self] = newValue }
    }
}
