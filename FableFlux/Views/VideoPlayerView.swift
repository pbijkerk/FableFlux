import SwiftUI
import WebKit
import AVKit

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
