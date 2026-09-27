import SwiftUI
import WebKit
import AVKit
import AVFoundation
import Observation

// MARK: - YouTube embed player

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.isOpaque = true
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.loadHTMLString(embedHTML, baseURL: nil)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}

    private var embedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { margin:0; padding:0; box-sizing:border-box; background:#000; }
        html, body { width:100%; height:100%; background:#000; }
        .wrap { position:relative; padding-bottom:56.25%; height:0; overflow:hidden; }
        .wrap iframe { position:absolute; top:0; left:0; width:100%; height:100%; border:0; }
        </style>
        </head>
        <body>
        <div class="wrap">
        <iframe src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
                allowfullscreen
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture">
        </iframe>
        </div>
        </body>
        </html>
        """
    }
}

// MARK: - Vimeo embed player

struct VimeoPlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.isOpaque = true
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.loadHTMLString(embedHTML, baseURL: nil)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}

    private var embedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { margin:0; padding:0; box-sizing:border-box; background:#000; }
        html, body { width:100%; height:100%; background:#000; }
        .wrap { position:relative; padding-bottom:56.25%; height:0; overflow:hidden; }
        .wrap iframe { position:absolute; top:0; left:0; width:100%; height:100%; border:0; }
        </style>
        </head>
        <body>
        <div class="wrap">
        <iframe src="https://player.vimeo.com/video/\(videoID)?playsinline=1"
                allowfullscreen
                allow="autoplay; fullscreen; picture-in-picture">
        </iframe>
        </div>
        </body>
        </html>
        """
    }
}

// MARK: - Native video player (AVPlayerViewController) voor directe MP4/video URLs

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

// MARK: - Audio player view model

@MainActor
@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var duration: Double = 0
    var currentTime: Double = 0
    var isLoading = true

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    func setup(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let item = AVPlayerItem(url: url)
        playerItem = item
        player = AVPlayer(playerItem: item)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .readyToPlay {
                    let secs = item.duration.seconds
                    if secs.isFinite && secs > 0 {
                        self.duration = secs
                    }
                    self.isLoading = false
                }
            }
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let secs = time.seconds
                if secs.isFinite && secs >= 0 {
                    self.currentTime = secs
                }
                // Update duration if not yet set (some streams report late)
                if self.duration == 0, let d = self.player?.currentItem?.duration.seconds,
                    d.isFinite && d > 0
                {
                    self.duration = d
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cleanup() {
        player?.pause()
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player = nil
        playerItem = nil
        isPlaying = false
    }
}

// MARK: - Audio player view

struct AudioPlayerView: View {
    let url: URL
    @State private var vm = AudioPlayerViewModel()

    var body: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { vm.currentTime },
                    set: { vm.seek(to: $0) }
                ),
                in: 0...max(1, vm.duration)
            )
            .disabled(vm.isLoading)
            .tint(.primary)

            HStack {
                Text(formatTime(vm.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if vm.isLoading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Button {
                        vm.togglePlayPause()
                    } label: {
                        Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                Text(vm.duration > 0 ? "-\(formatTime(vm.duration - vm.currentTime))" : "--:--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear { vm.setup(url: url) }
        .onDisappear { vm.cleanup() }
    }
}

private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}
