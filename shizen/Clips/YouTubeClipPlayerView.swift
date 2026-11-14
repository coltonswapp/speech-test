//
//  YouTubeClipPlayerView.swift
//  shizen
//
//  YouTube IFrame Player API in a WKWebView. JS posts the player time every
//  ~100 ms while playing; `currentTime` interpolates between samples so a
//  display link can drive per-frame karaoke. Nothing is drawn over the live
//  player (YouTube's terms forbid obscuring it); the thumbnail poster only
//  covers the empty web view until the embed reports ready.
//

import QuartzCore
import UIKit
import WebKit

final class YouTubeClipPlayerView: UIView {

    enum PlaybackState: Int {
        case unstarted = -1
        case ended = 0
        case playing = 1
        case paused = 2
        case buffering = 3
        case cued = 5
    }

    /// Embeds need an https referrer (error 153 without one).
    private static let embedOrigin = URL(string: "https://shizenapp.com")!
    private static let messageName = "clipPlayer"

    var onReady: (() -> Void)?
    var onStateChange: ((PlaybackState) -> Void)?
    var onError: ((Int) -> Void)?

    private(set) var state: PlaybackState = .unstarted
    private(set) var isReady = false
    /// Last rate YouTube confirmed (it may round a requested rate).
    private(set) var playbackRate: Double = 1
    /// YouTube's own control bar (`controls` player var). Fixed per load, so
    /// changing it reloads the embed (`setShowsControls`).
    private(set) var showsControls = true

    private var videoID: String?
    /// Where to pick up after a reload: exact time, whether it was playing, and the rate.
    private var pendingResume: (time: TimeInterval, play: Bool, rate: Double)?
    /// `play()` before the embed is ready starts as soon as it is (feed autoplay).
    private var playWhenReady = false

    private let webView: WKWebView
    /// Video thumbnail over the embed until the player is ready, so loading shows
    /// the clip instead of a black box. Aspect-fill crops hqdefault's letterbox /
    /// Shorts pillarbox bars to the frame.
    private let posterView = UIImageView()
    private var posterTask: Task<Void, Never>?
    private var sampleTime: TimeInterval = 0
    private var sampleHostTime: CFTimeInterval = CACurrentMediaTime()

    /// Interpolated video time (seconds).
    var currentTime: TimeInterval {
        guard state == .playing else { return sampleTime }
        return sampleTime + (CACurrentMediaTime() - sampleHostTime) * playbackRate
    }

    var isPlaying: Bool { state == .playing || state == .buffering }

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)

        configuration.userContentController.add(
            WeakScriptMessageHandler(self),
            name: Self.messageName
        )
        backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.backgroundColor = .black
        posterView.isUserInteractionEnabled = false
        posterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posterView)
        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: topAnchor),
            posterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: trailingAnchor),
            posterView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func showPoster(videoID: String) {
        posterTask?.cancel()
        posterView.image = nil
        posterView.alpha = 1
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard let url = URL(string: "https://i.ytimg.com/vi/\(safeID)/hqdefault.jpg") else { return }
        posterTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled,
                  let self, self.videoID == videoID, !self.isReady else { return }
            UIView.transition(with: self.posterView, duration: 0.2, options: .transitionCrossDissolve) {
                self.posterView.image = image
            }
        }
    }

    private func hidePoster() {
        posterTask?.cancel()
        posterTask = nil
        guard posterView.alpha > 0 else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.posterView.alpha = 0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(videoID: String, startSeconds: TimeInterval, showsControls: Bool) {
        // A controls-toggle reload of the same video keeps the live frame (no poster flash).
        if videoID != self.videoID { showPoster(videoID: videoID) }
        self.videoID = videoID
        self.showsControls = showsControls
        isReady = false
        state = .unstarted
        sampleTime = startSeconds
        sampleHostTime = CACurrentMediaTime()
        webView.loadHTMLString(
            Self.html(videoID: videoID, startSeconds: startSeconds, showsControls: showsControls),
            baseURL: Self.embedOrigin
        )
    }

    /// Reloads the embed with or without YouTube's controls, resuming at the
    /// current time (and playing again if it was playing).
    func setShowsControls(_ shows: Bool) {
        guard shows != showsControls, let videoID else { return }
        let time = currentTime
        pendingResume = (time, isPlaying, playbackRate)
        load(videoID: videoID, startSeconds: time, showsControls: shows)
        onStateChange?(state)
    }

    func play() {
        guard isReady else {
            playWhenReady = true
            return
        }
        webView.evaluateJavaScript("player && player.playVideo();")
    }

    func pause() {
        playWhenReady = false
        webView.evaluateJavaScript("player && player.pauseVideo();")
    }

    func setPlaybackRate(_ rate: Double) {
        webView.evaluateJavaScript(String(format: "player && player.setPlaybackRate(%.2f);", rate))
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, seconds)
        sampleTime = target
        sampleHostTime = CACurrentMediaTime()
        webView.evaluateJavaScript(String(format: "player && player.seekTo(%.3f, true);", target))
    }

    fileprivate func handle(message: Any) {
        guard let body = message as? [String: Any], let type = body["type"] as? String else { return }
        if let time = body["time"] as? Double, time.isFinite {
            sampleTime = time
            sampleHostTime = CACurrentMediaTime()
        }
        switch type {
        case "ready":
            isReady = true
            hidePoster()
            if let resume = pendingResume {
                pendingResume = nil
                if resume.rate != 1 { setPlaybackRate(resume.rate) }
                // `start` is whole seconds; seek for the exact spot only when
                // resuming playback (seeking a cued video can start it).
                if resume.play {
                    seek(to: resume.time)
                    play()
                }
            }
            if playWhenReady {
                playWhenReady = false
                play()
            }
            onReady?()
        case "state":
            let raw = (body["state"] as? Int) ?? -1
            state = PlaybackState(rawValue: raw) ?? .unstarted
            onStateChange?(state)
        case "rate":
            if let rate = body["rate"] as? Double, rate > 0 { playbackRate = rate }
        case "error":
            hidePoster()
            onError?((body["code"] as? Int) ?? -1)
        default:
            break
        }
    }

    private static func html(videoID: String, startSeconds: TimeInterval, showsControls: Bool) -> String {
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let start = max(0, Int(startSeconds.rounded(.down)))
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; inset: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
          var player = null;
          var timer = null;
          function post(msg) { window.webkit.messageHandlers.\(messageName).postMessage(msg); }
          function now() { return player && player.getCurrentTime ? player.getCurrentTime() : 0; }
          function startTimer() {
            stopTimer();
            timer = setInterval(function () { post({ type: "time", time: now() }); }, 100);
          }
          function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
          function onYouTubeIframeAPIReady() {
            player = new YT.Player("player", {
              videoId: "\(safeID)",
              playerVars: {
                playsinline: 1,
                start: \(start),
                controls: \(showsControls ? 1 : 0),
                rel: 0,
                modestbranding: 1,
                iv_load_policy: 3,
                cc_load_policy: 0,
                origin: "\(embedOrigin.absoluteString)"
              },
              events: {
                onReady: function () { post({ type: "ready", time: now() }); },
                onStateChange: function (e) {
                  post({ type: "state", state: e.data, time: now() });
                  if (e.data === 1) { startTimer(); } else { stopTimer(); }
                },
                onPlaybackRateChange: function (e) { post({ type: "rate", rate: e.data, time: now() }); },
                onError: function (e) { post({ type: "error", code: e.data }); }
              }
            });
          }
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body>
        </html>
        """
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: YouTubeClipPlayerView?

    init(_ target: YouTubeClipPlayerView) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.handle(message: message.body)
    }
}
