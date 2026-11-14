//
//  ClipPlayerViewController.swift
//  shizen
//
//  Experiment: a YouTube clip with a word-synced transcript (payload from
//  Studio → Experiments → Clip transcripts). The highlighted word follows the
//  player. Tapping a word pauses and shows its definition callout; tapping it
//  opens the dictionary sheet. Each line's chevron opens the sentence
//  breakdown. A vertical pager (same nested scroll handoff and seam chevron as
//  the dialogue lesson screen) holds two pages: player + transport + transcript,
//  then the clip's highlights when it has any. Paging away pauses the video.
//

import InteractionKit
import QuartzCore
import UIKit

final class ClipPlayerViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    private struct TokenRef: Equatable {
        let sentence: Int
        let token: Int
    }

    private struct TimedToken {
        let ref: TokenRef
        let start: TimeInterval
        let end: TimeInterval
    }

    private struct Row {
        let sentence: ClipPayload.Sentence
        let container: UIView
        let textView: LyricsInsetUnderlineTextView
        /// Pulls the text view left by its own leading inset so the glyphs line up
        /// with the timestamp and English. Updated after each `configure`.
        let textLeading: NSLayoutConstraint
        /// Studio translation under the line; nil when the clip has none for it.
        let englishLabel: UILabel?
        /// Token ranges in `sentence.textJP` (nil when a surface is not found in order).
        let tokenRanges: [NSRange?]
        let japaneseTokens: [JapaneseToken]?
    }

    /// Shorts player stops. Compact and medium are shares of the page height;
    /// full is as tall as fits above the transport bar (or as wide as the page allows).
    private enum PortraitDetent: String, CaseIterable {
        case compact
        case small
        case medium
        case full
    }
    private static let portraitCompactFraction: CGFloat = 0.3
    private static let portraitSmallFraction: CGFloat = 0.4
    private static let portraitMediumFraction: CGFloat = 0.5
    private static let portraitDetentKey = "clips.portraitPlayerDetent"
    /// How far ahead a release's velocity is projected when picking a detent.
    private static let detentProjectionSeconds: CGFloat = 0.2
    /// Past the smallest / largest detent, a drag moves the player this much per point.
    private static let detentRubberBand: CGFloat = 0.25
    /// Captions fade in over the last stretch of a drag toward the full detent.
    private static let captionFadeDistance: CGFloat = 80
    /// The transcript follows a wrapping line once the marker passes this share of the visible height.
    private static let wrapFollowThreshold: CGFloat = 0.6
    /// Wrap-following holds off this long after any auto-scroll so animations don't fight.
    private static let wrapFollowSettleSeconds: CFTimeInterval = 0.4
    /// Captions keep a finished line up this long before clearing.
    private static let captionHoldSeconds: TimeInterval = 1.5
    private static let resizeHandleHeight: CGFloat = 22
    /// Side margin the Shorts player may shrink to at the full detent.
    private static let fullDetentSideInset: CGFloat = 8
    /// Clip facts sit in a row along the player's top edge: gap under the nav bar, gap above the player.
    private static let infoRowTopPadding: CGFloat = 4
    private static let infoRowBottomPadding: CGFloat = 8
    /// Landscape: gap between the player's bottom edge and the top of the transcript.
    private static let landscapeGapBelowPlayer: CGFloat = 4
    /// Lines fade out over this band as they scroll up to the player; the first
    /// line rests just under it.
    private static let transcriptFadeHeight: CGFloat = 20
    /// Keep the last word lit this long after it ends (covers short pauses).
    private static let playerCornerRadius: CGFloat = 16
    private static let highlightHoldSeconds: TimeInterval = 0.6
    /// Start a replayed sentence slightly early so the first mora isn't clipped.
    private static let replayLeadInSeconds: TimeInterval = 0.15
    /// "Previous" restarts the current line unless it began less than this long ago.
    private static let previousLineGraceSeconds: TimeInterval = 1.2
    /// After the user scrolls, wait this long before auto-scrolling again.
    /// Extra room between tokens so neighbors are easier to tap.
    private static let tokenSpacing: CGFloat = 6
    /// Room between wrapped lines with furigana off, close to the ruby reserve.
    private static let plainLineSpacing: CGFloat = 10
    /// Same as the dialogue transport bar.
    private static let transportButtonSize: CGFloat = 50
    private static let transportGlyphPointSize: CGFloat = 22
    /// Dialogue transport bar: buttons 8 pt above the home indicator, 8 pt clear above.
    private static let transportBarVerticalPadding: CGFloat = 8
    private static let horizontalInset: CGFloat = 20
    private static let calloutGap: CGFloat = 6
    // Pager feel: same values as DialogueNestedPagingExperimentViewController.
    private static let pageCommitThreshold: CGFloat = 0.52
    private static let pageVelocityThreshold: CGFloat = 1.15
    private static let pageTransitionResistance: CGFloat = 0.52
    private static let seamChevronSize: CGFloat = 52
    private static let seamChevronPointSize: CGFloat = 22
    private static let playbackRates: [Double] = [0.5, 0.75, 1, 1.25]
    /// Remembered across clips. Off by default: our transport bar drives playback.
    private static let showsYouTubeControlsKey = "clipPlayer.showsYouTubeControls"
    private static var showsYouTubeControls: Bool {
        get { UserDefaults.standard.bool(forKey: showsYouTubeControlsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showsYouTubeControlsKey) }
    }

    /// Experiment (options menu): highlights open from a transport-bar button as a
    /// sheet instead of a second vertical page under the transcript.
    private static let highlightsInSheetKey = "clipPlayer.highlightsInSheet"
    private static var highlightsInSheet: Bool {
        get { UserDefaults.standard.bool(forKey: highlightsInSheetKey) }
        set { UserDefaults.standard.set(newValue, forKey: highlightsInSheetKey) }
    }

    /// Set by `ClipFeedViewController` before the view loads: this screen is one page of
    /// a vertical feed, so highlights always open as a sheet (the feed owns vertical paging).
    var isInFeed = false
    /// A feed page sits at an arbitrary offset in the feed's scroll view, so its own safe
    /// area wobbles mid-swipe; the feed passes its (stable) insets instead.
    var feedSafeAreaInsets: UIEdgeInsets? {
        didSet {
            guard isViewLoaded, oldValue != feedSafeAreaInsets else { return }
            view.setNeedsLayout()
        }
    }
    private var safeInsets: UIEdgeInsets { feedSafeAreaInsets ?? view.safeAreaInsets }
    /// The transcript: the feed's scroll handoff drives this as the page's inner scroll view.
    var transcriptScrollView: UIScrollView { scrollView }
    var navigationMenuItem: UIBarButtonItem? { navigationItem.rightBarButtonItem }

    /// Vertical swipe on the video: +1 = next clip, -1 = previous.
    var onSwipeToAdjacentClip: ((Int) -> Void)?
    private lazy var feedSwipePan = UIPanGestureRecognizer(target: self, action: #selector(playerSwiped(_:)))

    /// Feed autoplay: starts now, or as soon as the embed is ready.
    func startPlayback() {
        playerView.play()
    }

    @objc private func playerSwiped(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let translation = pan.translation(in: view).y
        let velocity = pan.velocity(in: view).y
        guard abs(translation) > 48 || abs(velocity) > 600 else { return }
        onSwipeToAdjacentClip?(translation < 0 ? 1 : -1)
    }

    /// Leaving a feed page: stop audio and close any open callout.
    func pausePlayback() {
        playerView.pause()
        dismissCallout(animated: false)
    }

    private let clipID: String
    private let preview: ClipSummary?
    private var payload: ClipPayload?
    /// What the embed was last loaded with, so the payload doesn't reload a preview-started player.
    private var loadedMedia: (videoID: String, startSec: Double)?

    private let playerView = YouTubeClipPlayerView()
    /// Clip facts under the player: duration, line count, highlight counts.
    private let clipInfoLabel = UILabel()
    private let transportBar = UIView()
    /// The bottom transport bar shapes the transcript's soft bottom edge (dialogue pattern).
    private let transportEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()
    private var transportButtonsBottom: NSLayoutConstraint!
    private let previousButton = GlassIconButton(
        symbolName: "backward.fill",
        pointSize: ClipPlayerViewController.transportGlyphPointSize,
        glyphDimension: ClipPlayerViewController.transportGlyphPointSize + 4,
        accessibilityLabel: "Previous line"
    )
    private let playPauseButton = GlassIconButton(
        symbolName: "play.fill",
        pointSize: ClipPlayerViewController.transportGlyphPointSize,
        glyphDimension: ClipPlayerViewController.transportGlyphPointSize + 4,
        accessibilityLabel: "Play"
    )
    /// Next to rewind; shown only while the transcript isn't following playback.
    private let recenterButton = GlassIconButton(
        symbolName: "text.line.first.and.arrowtriangle.forward",
        pointSize: ClipPlayerViewController.transportGlyphPointSize,
        glyphDimension: ClipPlayerViewController.transportGlyphPointSize + 4,
        accessibilityLabel: "Follow transcript"
    )
    /// Left of play; sheet mode only (see `highlightsInSheet`).
    private let highlightsButton = GlassIconButton(
        symbolName: "text.book.closed",
        pointSize: ClipPlayerViewController.transportGlyphPointSize,
        glyphDimension: ClipPlayerViewController.transportGlyphPointSize + 4,
        accessibilityLabel: "Highlights"
    )
    private let elapsedLabel = UILabel()
    /// Outer vertical pager under the transport bar: transcript, then highlights.
    private let outerScrollView = UIScrollView()
    private let pagesStack = UIStackView()
    private let transcriptPage = UIView()
    private let highlightsPage = UIView()
    private var highlightsPageHeight: NSLayoutConstraint!
    /// Transcript (page 0).
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    /// VOCAB / GRAMMAR / notes from Studio (page 1), like a lesson's highlights page.
    private let highlightsScrollView = UIScrollView()
    private let highlightsView = DialogueLearningHighlightsContentView()
    private var hasHighlightsPage = false
    private var handoffCoordinator: NestedVerticalScrollHandoffCoordinator?
    private var activePage = 0
    /// Playing when we paged to highlights; resume on the way back.
    private var resumeOnTranscriptPage = false
    private let seamChevron = UIButton(type: .system)
    private var seamChevronCenterY: NSLayoutConstraint!
    private var seamPointsUp = false
    private let seamScrollEdgeInteraction = UIScrollEdgeElementContainerInteraction()
    /// Pages run edge to edge under the nav bar (dialogue lesson pattern); the
    /// player is pushed down by the safe-area top on page 0.
    private var playerTop: NSLayoutConstraint!
    private var landscapePlayerConstraints: [NSLayoutConstraint] = []
    private var portraitPlayerConstraints: [NSLayoutConstraint] = []
    private var portraitPlayerHeight: NSLayoutConstraint!
    /// Drag under the Shorts player to move between detents; remembered across clips.
    private let resizeHandle = ClipPlayerResizeHandle()
    private var edgeBelowPlayer: NSLayoutConstraint!
    private var edgeBelowHandle: NSLayoutConstraint!
    private var isPortraitLayout = false
    private var portraitDetent: PortraitDetent = {
        let stored = UserDefaults.standard.string(forKey: ClipPlayerViewController.portraitDetentKey)
        return stored.flatMap(PortraitDetent.init(rawValue:)) ?? .medium
    }()
    private var resizeStartHeight: CGFloat = 0
    /// Tick as a drag passes a detent; a light tap when the player settles on a new one.
    private lazy var detentCrossHaptic = UISelectionFeedbackGenerator(view: resizeHandle)
    private lazy var detentLandHaptic = UIImpactFeedbackGenerator(style: .light, view: resizeHandle)
    /// True from drag start until the snap animation lands; layout passes leave the height alone.
    private var isResizingPlayer = false
    /// Spans the info row above the player down to the handle under it (or a
    /// small gap under a landscape player); the transcript starts at its bottom.
    private let infoEdgeContainer: UIView = {
        let view = ClipPassthroughView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    /// Hosts the transcript and fades its top edge where lines slide under the player.
    private let transcriptFadeView = ClipTopFadeView()
    /// Spoken line over the bottom fifth of the Shorts player at the full detent.
    private let captionOverlay = ClipCaptionOverlayView()
    /// Last token started (drives the caption's spoken part); nil before the first word.
    private var captionToken: TokenRef?
    /// Host-owned anchor for the top edge effect, like the dialogue lesson, so the
    /// strip under the nav bar matches on every page.
    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()
    private let topScrollEdgeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()
    private let statusLabel = UILabel()
    /// Covers the player on a deprecated clip (video deleted or delisted).
    private let unavailableLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private let lyricFont = UIFont.systemFont(ofSize: 22, weight: .regular)
    private var showsFurigana = true
    private var showsEnglish = true
    private var loopsClip = true
    private var rows: [Row] = []
    private var timeline: [TimedToken] = []
    private var activeToken: TokenRef?
    private var activeSentence: Int?
    /// Token whose compact definition callout is showing.
    private var calloutToken: TokenRef?
    private var displayLink: CADisplayLink?
    private var isUserScrolling = false
    /// Transcript follows the spoken line until the learner scrolls it; the
    /// recenter button (or rewind / a line's timestamp) turns following back on.
    private var isFollowingPlayback = true
    private var lastLoopSeekTime: CFTimeInterval = 0
    /// When the transcript last auto-scrolled; wrap-following waits for that to settle.
    private var lastAutoScrollTime: CFTimeInterval = 0
    private var lastElapsedSecond = -1
    private var shownPlaying = false

    /// From the list row: lets the screen take the clip's final shape and start
    /// the embed before the full payload arrives.
    init(clipID: String, title: String? = nil, preview: ClipSummary? = nil) {
        self.clipID = clipID
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
        self.title = title ?? preview?.title ?? clipID
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never
        configureLayout()
        configureOptionsMenu()
        configurePlayerCallbacks()
        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.delegate = self
        view.addGestureRecognizer(backgroundTap)
        if isInFeed {
            // The transcript hands off at its edges; the video can be flicked directly.
            feedSwipePan.delegate = self
            feedSwipePan.cancelsTouchesInView = false
            playerView.addGestureRecognizer(feedSwipePan)
        }
        applyPreview()
        load()
    }

    /// Final player shape, poster, and clip facts from the list row, so nothing
    /// jumps when the payload lands (a Short never starts as a 16:9 frame).
    private func applyPreview() {
        guard let preview else { return }
        applyPlayerOrientation(portrait: preview.isPortrait)
        loadPlayer(videoID: preview.videoID, startSec: preview.startSec)
        setClipInfo([
            Self.formatTime(max(0, preview.endSec - preview.startSec)),
            Self.counted(preview.sentenceCount, "line", "lines"),
        ])
    }

    private func loadPlayer(videoID: String, startSec: Double) {
        if let loadedMedia, loadedMedia.videoID == videoID, loadedMedia.startSec == startSec { return }
        loadedMedia = (videoID, startSec)
        playerView.load(videoID: videoID, startSeconds: startSec, showsControls: Self.showsYouTubeControls)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerView.pause()
        dismissCallout(animated: false)
        stopDisplayLink()
    }

    // MARK: - Layout

    private func configureLayout() {
        configurePager()

        // Page 0: player, transport bar, transcript.
        playerView.translatesAutoresizingMaskIntoConstraints = false
        transcriptPage.addSubview(playerView)

        clipInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        clipInfoLabel.font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .medium
        )
        clipInfoLabel.textColor = .secondaryLabel
        clipInfoLabel.textAlignment = .center
        clipInfoLabel.numberOfLines = 1
        clipInfoLabel.adjustsFontSizeToFitWidth = true
        clipInfoLabel.minimumScaleFactor = 0.8
        // Handle and info row live in the edge container, so the transcript's top
        // edge effect takes its shape from them as lines scroll underneath.
        infoEdgeContainer.addSubview(clipInfoLabel)

        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.isHidden = true
        resizeHandle.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(resizeHandlePanned(_:)))
        )
        resizeHandle.onAdjust = { [weak self] step in
            self?.stepPortraitDetent(by: Int(step))
        }
        infoEdgeContainer.addSubview(resizeHandle)

        captionOverlay.translatesAutoresizingMaskIntoConstraints = false
        captionOverlay.alpha = 0
        captionOverlay.layer.cornerRadius = Self.playerCornerRadius
        captionOverlay.layer.cornerCurve = .continuous
        captionOverlay.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        transcriptPage.addSubview(captionOverlay)

        // Transcript starts at the player's bottom edge (under the Shorts grabber)
        // and fades out there: lines never show beside or above the player, and
        // a resize just moves the transcript's top with the player.
        configureInnerScrollView(scrollView)
        // The fade replaces the system top edge effect for the transcript.
        scrollView.topEdgeEffect.isHidden = true
        transcriptFadeView.translatesAutoresizingMaskIntoConstraints = false
        transcriptFadeView.fadeHeight = Self.transcriptFadeHeight
        transcriptFadeView.addSubview(scrollView)
        transcriptPage.insertSubview(transcriptFadeView, at: 0)
        transcriptPage.addSubview(infoEdgeContainer)
        stack.axis = .vertical
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        // Page 1: highlights.
        configureInnerScrollView(highlightsScrollView)
        highlightsPage.addSubview(highlightsScrollView)
        // Same as the dialogue lesson's highlights page: the content view straight
        // in the scroll view (its own VOCAB / GRAMMAR / notes titles, no page header).
        highlightsView.translatesAutoresizingMaskIntoConstraints = false
        highlightsScrollView.addSubview(highlightsView)
        highlightsView.onSelectVocabulary = { [weak self] word in
            self?.presentVocabulary(word)
        }
        highlightsView.onSelectGrammar = { [weak self] pattern in
            self?.presentGrammar(pattern)
        }

        configureTransportBar()
        configureSeamChevron()
        installHandoffCoordinator()

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        unavailableLabel.font = .preferredFont(forTextStyle: .subheadline)
        unavailableLabel.adjustsFontForContentSizeCategory = true
        unavailableLabel.textColor = .white
        unavailableLabel.backgroundColor = .black
        unavailableLabel.numberOfLines = 0
        unavailableLabel.textAlignment = .center
        unavailableLabel.isHidden = true
        unavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        playerView.addSubview(unavailableLabel)
        NSLayoutConstraint.activate([
            unavailableLabel.topAnchor.constraint(equalTo: playerView.topAnchor),
            unavailableLabel.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
            unavailableLabel.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            unavailableLabel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
        ])

        // Above the pager, like the dialogue lesson's top edge host.
        view.addSubview(topScrollEdgeContainer)
        topScrollEdgeContainer.addInteraction(topScrollEdgeInteraction)
        topScrollEdgeInteraction.scrollView = scrollView

        playerTop = playerView.topAnchor.constraint(equalTo: transcriptPage.topAnchor)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topScrollEdgeContainer.topAnchor.constraint(equalTo: view.topAnchor),
            topScrollEdgeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topScrollEdgeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topScrollEdgeContainer.bottomAnchor.constraint(equalTo: guide.topAnchor),

            playerTop,
            playerView.centerXAnchor.constraint(equalTo: transcriptPage.centerXAnchor),
            playerView.widthAnchor.constraint(lessThanOrEqualTo: transcriptPage.widthAnchor),

            resizeHandle.topAnchor.constraint(equalTo: playerView.bottomAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: transcriptPage.centerXAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 120),
            resizeHandle.heightAnchor.constraint(equalToConstant: Self.resizeHandleHeight),

            clipInfoLabel.leadingAnchor.constraint(equalTo: transcriptPage.leadingAnchor, constant: Self.horizontalInset),
            clipInfoLabel.trailingAnchor.constraint(equalTo: transcriptPage.trailingAnchor, constant: -Self.horizontalInset),

            captionOverlay.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            captionOverlay.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            captionOverlay.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
            // Bottom fifth of the player; grows for a long line (up to half).
            captionOverlay.heightAnchor.constraint(greaterThanOrEqualTo: playerView.heightAnchor, multiplier: 0.2),
            {
                let fifth = captionOverlay.heightAnchor.constraint(equalTo: playerView.heightAnchor, multiplier: 0.2)
                fifth.priority = .defaultLow
                return fifth
            }(),
            {
                let cap = captionOverlay.heightAnchor.constraint(lessThanOrEqualTo: playerView.heightAnchor, multiplier: 0.5)
                cap.priority = .defaultHigh
                return cap
            }(),

            // Info row along the player's top edge.
            clipInfoLabel.bottomAnchor.constraint(equalTo: playerView.topAnchor, constant: -Self.infoRowBottomPadding),

            infoEdgeContainer.topAnchor.constraint(equalTo: clipInfoLabel.topAnchor, constant: -Self.infoRowTopPadding),
            infoEdgeContainer.leadingAnchor.constraint(equalTo: transcriptPage.leadingAnchor),
            infoEdgeContainer.trailingAnchor.constraint(equalTo: transcriptPage.trailingAnchor),

            transcriptFadeView.topAnchor.constraint(equalTo: infoEdgeContainer.bottomAnchor),
            transcriptFadeView.leadingAnchor.constraint(equalTo: transcriptPage.leadingAnchor),
            transcriptFadeView.trailingAnchor.constraint(equalTo: transcriptPage.trailingAnchor),
            transcriptFadeView.bottomAnchor.constraint(equalTo: transcriptPage.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: transcriptFadeView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: transcriptFadeView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: transcriptFadeView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: transcriptFadeView.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -8),

            highlightsScrollView.topAnchor.constraint(equalTo: highlightsPage.topAnchor),
            highlightsScrollView.leadingAnchor.constraint(equalTo: highlightsPage.leadingAnchor),
            highlightsScrollView.trailingAnchor.constraint(equalTo: highlightsPage.trailingAnchor),
            highlightsScrollView.bottomAnchor.constraint(equalTo: highlightsPage.bottomAnchor),

            highlightsView.topAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.topAnchor, constant: 8),
            highlightsView.leadingAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            highlightsView.trailingAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            highlightsView.bottomAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            highlightsView.widthAnchor.constraint(equalTo: highlightsScrollView.frameLayoutGuide.widthAnchor, constant: -40),

            statusLabel.centerYAnchor.constraint(equalTo: outerScrollView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
            spinner.centerXAnchor.constraint(equalTo: outerScrollView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: outerScrollView.centerYAnchor),
        ])
        edgeBelowPlayer = infoEdgeContainer.bottomAnchor.constraint(
            equalTo: playerView.bottomAnchor, constant: Self.landscapeGapBelowPlayer
        )
        edgeBelowHandle = infoEdgeContainer.bottomAnchor.constraint(equalTo: resizeHandle.bottomAnchor, constant: 2)
        edgeBelowPlayer.isActive = true
        // Landscape: a rounded 16:9 card inside the page's side insets.
        landscapePlayerConstraints = [
            playerView.widthAnchor.constraint(equalTo: transcriptPage.widthAnchor, constant: -Self.horizontalInset * 2),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 9.0 / 16.0),
        ]
        // Shorts: a centered 9:16 frame taking a fixed share of the page height,
        // leaving the transcript below it as in the landscape layout.
        // Height is set from `portraitDetent` once the page has a size (updateInnerInsets).
        portraitPlayerHeight = playerView.heightAnchor.constraint(equalToConstant: 300)
        portraitPlayerConstraints = [
            portraitPlayerHeight,
            playerView.widthAnchor.constraint(equalTo: playerView.heightAnchor, multiplier: 9.0 / 16.0),
        ]
        NSLayoutConstraint.activate(landscapePlayerConstraints)
    }

    /// Swaps the player between the 16:9 full-width frame and the centered 9:16 Shorts frame.
    private func applyPlayerOrientation(portrait: Bool) {
        isPortraitLayout = portrait
        if portrait { updatePortraitPlayerHeight() }
        NSLayoutConstraint.deactivate(portrait ? landscapePlayerConstraints : portraitPlayerConstraints)
        NSLayoutConstraint.activate(portrait ? portraitPlayerConstraints : landscapePlayerConstraints)
        edgeBelowPlayer.isActive = !portrait
        edgeBelowHandle.isActive = portrait
        resizeHandle.isHidden = !portrait
        // Both shapes are rounded cards inset from the page edges.
        playerView.layer.cornerRadius = Self.playerCornerRadius
        playerView.layer.cornerCurve = .continuous
        playerView.clipsToBounds = true
        updateCaptionOverlayVisibility()
    }

    // MARK: - Shorts player detents

    /// Player height at each detent for the current page size, ascending. Full is
    /// the tallest that still clears the info row and transport bar, and never
    /// wider than the page minus its side insets.
    private func portraitDetentHeights() -> [(detent: PortraitDetent, height: CGFloat)]? {
        let pageHeight = transcriptPage.bounds.height
        let pageWidth = transcriptPage.bounds.width
        guard pageHeight > 0, pageWidth > 0 else { return nil }
        // Full clears the info row above, the grabber and transport bar below, and
        // may run nearly edge to edge.
        let widthCap = (pageWidth - Self.fullDetentSideInset * 2) * 16.0 / 9.0
        let belowPlayer = Self.resizeHandleHeight
            + safeInsets.bottom + Self.transportBarVerticalPadding * 2 + Self.transportButtonSize
        let full = max(0, min(widthCap, pageHeight - safeInsets.top - infoRowHeight - belowPlayer))
        // Compact and medium keep the page's side insets.
        let insetWidthCap = (pageWidth - Self.horizontalInset * 2) * 16.0 / 9.0
        let medium = min(pageHeight * Self.portraitMediumFraction, full, insetWidthCap)
        let small = min(pageHeight * Self.portraitSmallFraction, medium)
        let compact = min(pageHeight * Self.portraitCompactFraction, small)
        return [(.compact, compact), (.small, small), (.medium, medium), (.full, full)]
    }

    private func portraitHeight(for detent: PortraitDetent) -> CGFloat? {
        portraitDetentHeights()?.first { $0.detent == detent }?.height
    }

    /// Re-applies the current detent after the page size changes.
    private func updatePortraitPlayerHeight() {
        guard let height = portraitHeight(for: portraitDetent) else { return }
        if abs(portraitPlayerHeight.constant - height) > 0.5 {
            portraitPlayerHeight.constant = height
        }
        updateCaptionOverlayVisibility()
    }

    /// Follows the finger, with rubber-banding past the smallest and largest detents.
    private func dragPortraitPlayer(to proposed: CGFloat) {
        guard let heights = portraitDetentHeights(),
              let lower = heights.first?.height,
              let upper = heights.last?.height else { return }
        let height: CGFloat
        if proposed > upper {
            height = upper + (proposed - upper) * Self.detentRubberBand
        } else if proposed < lower {
            height = lower - (lower - proposed) * Self.detentRubberBand
        } else {
            height = proposed
        }
        let previous = portraitPlayerHeight.constant
        // Strictly passing a detent (opposite sides); leaving the one the drag started on doesn't count.
        if heights.contains(where: { (previous - $0.height) * (height - $0.height) < 0 }) {
            detentCrossHaptic.selectionChanged()
            detentCrossHaptic.prepare()
        }
        portraitPlayerHeight.constant = height
        transcriptPage.layoutIfNeeded()
        updateInnerInsets()
        updateCaptionOverlayVisibility()
    }

    /// Springs to `detent`; `velocity` (pt/s, + = taller) carries the drag into the spring.
    private func snapPortraitPlayer(to detent: PortraitDetent, velocity: CGFloat = 0) {
        guard let target = portraitHeight(for: detent) else { return }
        if detent != portraitDetent {
            detentLandHaptic.impactOccurred()
        }
        portraitDetent = detent
        UserDefaults.standard.set(detent.rawValue, forKey: Self.portraitDetentKey)
        let distance = target - portraitPlayerHeight.constant
        let relativeVelocity = abs(distance) > 1 ? velocity / distance : 0
        isResizingPlayer = true
        portraitPlayerHeight.constant = target
        UIView.animate(
            springDuration: 0.45,
            bounce: 0.12,
            initialSpringVelocity: relativeVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.transcriptPage.layoutIfNeeded()
            // Inside the animation so the transcript's offset glides with the player.
            self.updateInnerInsets()
            self.updateCaptionOverlayVisibility()
        } completion: { _ in
            self.isResizingPlayer = false
            // Keep the spoken line in view under the new player size.
            if self.isFollowingPlayback, let activeSentence = self.activeSentence {
                self.autoScroll(toRow: activeSentence)
            }
        }
    }

    /// VoiceOver adjustable: one detent taller (+1) or shorter (-1).
    private func stepPortraitDetent(by step: Int) {
        let all = PortraitDetent.allCases
        guard let index = all.firstIndex(of: portraitDetent) else { return }
        let next = min(max(index + step, 0), all.count - 1)
        guard next != index else { return }
        dismissCallout(animated: true)
        snapPortraitPlayer(to: all[next])
    }

    @objc private func resizeHandlePanned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            isResizingPlayer = true
            resizeStartHeight = portraitPlayerHeight.constant
            detentCrossHaptic.prepare()
            detentLandHaptic.prepare()
            dismissCallout(animated: true)
            resizeHandle.setActive(true)
        case .changed:
            dragPortraitPlayer(to: resizeStartHeight + pan.translation(in: transcriptPage).y)
        case .ended, .cancelled, .failed:
            resizeHandle.setActive(false)
            let velocity = pan.state == .ended ? pan.velocity(in: transcriptPage).y : 0
            let projected = portraitPlayerHeight.constant + velocity * Self.detentProjectionSeconds
            let nearest = portraitDetentHeights()?
                .min { abs($0.height - projected) < abs($1.height - projected) }?
                .detent ?? portraitDetent
            snapPortraitPlayer(to: nearest, velocity: velocity)
        default:
            break
        }
    }

    // MARK: - Caption overlay

    /// Captions show over the Shorts player only near the full detent, where the
    /// transcript has little room; they fade in over the last stretch of the drag.
    private func updateCaptionOverlayVisibility() {
        var alpha: CGFloat = 0
        if isPortraitLayout, let full = portraitHeight(for: .full), full > 0 {
            let progress = (portraitPlayerHeight.constant - (full - Self.captionFadeDistance)) / Self.captionFadeDistance
            alpha = min(max(progress, 0), 1)
        }
        if abs(captionOverlay.alpha - alpha) > 0.001 {
            captionOverlay.alpha = alpha
            // The captions replace the transcript at the full detent: cross-fade them.
            // Clip facts stay; they sit above the player, clear of the captions.
            scrollView.alpha = 1 - alpha
        }
        let captionsOnly = alpha > 0.99
        scrollView.accessibilityElementsHidden = captionsOnly
        captionOverlay.accessibilityElementsHidden = !captionsOnly
    }

    /// Spoken line with the words said so far at full strength; the English under it when shown.
    private func updateCaptionOverlay() {
        guard let ref = captionToken, rows.indices.contains(ref.sentence) else {
            captionOverlay.setLine(japanese: nil, spokenLength: 0, english: nil)
            return
        }
        let row = rows[ref.sentence]
        let spokenLength = row.tokenRanges.indices.contains(ref.token)
            ? row.tokenRanges[ref.token].map(NSMaxRange) ?? 0
            : 0
        captionOverlay.setLine(
            japanese: row.sentence.textJP,
            spokenLength: spokenLength,
            english: showsEnglish ? row.sentence.textEN : nil
        )
    }

    /// Outer pager: scrolled only by the handoff coordinator (inner overflow) and
    /// the seam chevron, like the dialogue lesson screen.
    private func configurePager() {
        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.isPagingEnabled = true
        outerScrollView.showsVerticalScrollIndicator = false
        outerScrollView.showsHorizontalScrollIndicator = false
        outerScrollView.alwaysBounceVertical = false
        outerScrollView.bounces = true
        outerScrollView.isScrollEnabled = false
        outerScrollView.decelerationRate = .fast
        outerScrollView.delaysContentTouches = false
        outerScrollView.contentInsetAdjustmentBehavior = .never
        outerScrollView.clipsToBounds = true
        outerScrollView.backgroundColor = ExperimentPalette.pageBackground
        outerScrollView.delegate = self
        view.addSubview(outerScrollView)

        pagesStack.axis = .vertical
        pagesStack.alignment = .fill
        pagesStack.spacing = 0
        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.addSubview(pagesStack)
        [transcriptPage, highlightsPage].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.backgroundColor = ExperimentPalette.pageBackground
            pagesStack.addArrangedSubview($0)
        }
        // Highlights page stays collapsed (one-page pager) until the clip has highlights.
        highlightsPage.isHidden = true
        highlightsPageHeight = highlightsPage.heightAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.heightAnchor)

        NSLayoutConstraint.activate([
            outerScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pagesStack.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor),

            transcriptPage.heightAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    /// Insets are managed by hand (`updateInnerInsets`): top clears the
    /// transport bar, bottom clears the home indicator and seam chevron.
    private func configureInnerScrollView(_ inner: UIScrollView) {
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.alwaysBounceVertical = true
        inner.delaysContentTouches = false
        inner.contentInsetAdjustmentBehavior = .never
        inner.topEdgeEffect.style = .soft
        inner.topEdgeEffect.isHidden = false
        inner.bottomEdgeEffect.style = .soft
        inner.bottomEdgeEffect.isHidden = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInnerInsets()
        updateSeamChevron()
    }

    /// Clip facts row between the nav bar and the player's top edge.
    private var infoRowHeight: CGFloat {
        Self.infoRowTopPadding + ceil(clipInfoLabel.font.lineHeight) + Self.infoRowBottomPadding
    }

    private func updateInnerInsets() {
        let safeBottom = safeInsets.bottom
        let safeTop = safeInsets.top
        let playerTopInset = safeTop + infoRowHeight
        if playerTop.constant != playerTopInset {
            playerTop.constant = playerTopInset
        }
        if isPortraitLayout, !isResizingPlayer {
            updatePortraitPlayerHeight()
        }
        let pairs: [(UIScrollView, UIEdgeInsets)] = [
            // Transcript's frame starts under the player; its first line rests just
            // below the fade. It scrolls under the bottom transport bar (which also
            // holds the seam chevron).
            (scrollView, UIEdgeInsets(
                top: Self.transcriptFadeHeight,
                left: 0,
                bottom: safeBottom + Self.transportBarVerticalPadding * 2 + Self.transportButtonSize + 16,
                right: 0
            )),
            // Dialogue highlights page: clear the nav bar, the resting up-chevron, and a 4 pt band.
            (highlightsScrollView, UIEdgeInsets(
                top: safeTop + Self.seamChevronSize + 4,
                left: 0,
                bottom: safeBottom + 16,
                right: 0
            )),
        ]
        let buttonsBottom = -(safeBottom + Self.transportBarVerticalPadding)
        if transportButtonsBottom.constant != buttonsBottom {
            transportButtonsBottom.constant = buttonsBottom
        }
        // With highlights, the page chevron takes the bar's center slot (as in the dialogue lesson).
        elapsedLabel.isHidden = hasHighlightsPage
        for (inner, insets) in pairs {
            guard inner.contentInset != insets else { continue }
            let topDelta = insets.top - inner.contentInset.top
            inner.contentInset = insets
            inner.verticalScrollIndicatorInsets = insets
            // Keep lines where they were when an inset first applies or changes.
            if inner === scrollView, !inner.isDragging, !inner.isDecelerating {
                inner.contentOffset.y -= topDelta
            }
        }
    }

    private func installHandoffCoordinator() {
        let coordinator = NestedVerticalScrollHandoffCoordinator(
            outerScrollView: outerScrollView,
            innerScrollViews: [scrollView, highlightsScrollView],
            pageCommitThreshold: Self.pageCommitThreshold,
            velocityThreshold: Self.pageVelocityThreshold,
            pageTransitionResistance: Self.pageTransitionResistance
        )
        coordinator.forwardingDelegate = self
        coordinator.onPageTransitionProgressChanged = { [weak self] _ in
            self?.updateSeamChevron()
        }
        coordinator.onPageChanged = { [weak self] page in
            self?.pageDidChange(to: page)
        }
        handoffCoordinator = coordinator
    }

    /// The player scrolls off with page 0, and YouTube doesn't allow playing a
    /// video the user can't see: pause on the way to highlights, resume on return.
    private func pageDidChange(to page: Int) {
        guard page != activePage else { return }
        activePage = page
        topScrollEdgeInteraction.scrollView = page == 0 ? scrollView : highlightsScrollView
        dismissCallout(animated: true)
        if page == 0 {
            if resumeOnTranscriptPage { playerView.play() }
            resumeOnTranscriptPage = false
        } else {
            resumeOnTranscriptPage = playerView.isPlaying
            playerView.pause()
        }
    }

    // MARK: - Seam chevron

    private func configureSeamChevron() {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        seamChevron.configuration = config
        seamChevron.translatesAutoresizingMaskIntoConstraints = false
        seamChevron.alpha = 0
        seamChevron.isUserInteractionEnabled = false
        seamChevron.addInteraction(seamScrollEdgeInteraction)
        applySeamChevronDirection(pointsUp: false)
        seamChevron.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.handoffCoordinator?.snapToPage(self.seamPointsUp ? 0 : 1)
        }, for: .primaryActionTriggered)
        view.addSubview(seamChevron)

        seamChevronCenterY = seamChevron.centerYAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            seamChevron.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            seamChevronCenterY,
            seamChevron.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.seamChevronSize),
            seamChevron.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.seamChevronSize),
        ])
    }

    /// The chevron tracks the page seam along a rail: bottom of the screen while
    /// the transcript shows, just under the transport bar on the highlights page.
    private func updateSeamChevron() {
        let pageHeight = outerScrollView.bounds.height
        guard hasHighlightsPage, pageHeight > 0 else {
            seamChevron.alpha = 0
            seamChevron.isUserInteractionEnabled = false
            seamScrollEdgeInteraction.scrollView = nil
            return
        }
        let seamViewportY = pageHeight - outerScrollView.contentOffset.y
        let travel = 1 - min(max(seamViewportY / pageHeight, 0), 1)
        let topRest = safeInsets.top + Self.seamChevronSize / 2
        // Same row as the transport buttons' centers (dialogue: safe bottom − 33).
        let bottomRest = view.bounds.height - safeInsets.bottom
            - Self.transportBarVerticalPadding - Self.transportButtonSize / 2
        let centerY = bottomRest + (topRest - bottomRest) * travel
        if abs(seamChevronCenterY.constant - centerY) > 0.25 {
            seamChevronCenterY.constant = centerY
        }
        seamChevron.alpha = 1
        seamChevron.isUserInteractionEnabled = true

        let pointsUp = seamViewportY < pageHeight * 0.5
        if pointsUp != seamPointsUp {
            seamPointsUp = pointsUp
            applySeamChevronDirection(pointsUp: pointsUp)
        }
        seamScrollEdgeInteraction.edge = pointsUp ? .top : .bottom
        seamScrollEdgeInteraction.scrollView = pointsUp ? highlightsScrollView : scrollView
        seamChevron.accessibilityLabel = pointsUp ? "Back to transcript" : "Show highlights"
    }

    private func applySeamChevronDirection(pointsUp: Bool) {
        seamChevron.setImage(
            UIImage(
                systemName: pointsUp ? "chevron.compact.up" : "chevron.compact.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Self.seamChevronPointSize, weight: .medium)
            ),
            for: .normal
        )
    }

    /// Bottom bar like the dialogue lesson: previous line on the left, play on the
    /// right, and the page chevron (or elapsed time) between them. The bar hosts
    /// the scroll-edge interaction, so the transcript softens around the glass buttons.
    private func configureTransportBar() {
        transportBar.translatesAutoresizingMaskIntoConstraints = false
        transportBar.backgroundColor = .clear
        transportBar.addInteraction(transportEdgeInteraction)
        transportEdgeInteraction.scrollView = scrollView
        transcriptPage.addSubview(transportBar)

        previousButton.addAction(UIAction { [weak self] _ in self?.previousTapped() }, for: .primaryActionTriggered)
        playPauseButton.addAction(UIAction { [weak self] _ in self?.playPauseTapped() }, for: .primaryActionTriggered)
        highlightsButton.addAction(UIAction { [weak self] _ in self?.presentHighlightsSheet() }, for: .primaryActionTriggered)
        highlightsButton.translatesAutoresizingMaskIntoConstraints = false
        highlightsButton.isHidden = true
        recenterButton.addAction(UIAction { [weak self] _ in
            self?.resumeFollowingPlayback(scroll: true)
        }, for: .primaryActionTriggered)
        recenterButton.translatesAutoresizingMaskIntoConstraints = false
        recenterButton.alpha = 0
        recenterButton.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        recenterButton.isUserInteractionEnabled = false
        recenterButton.accessibilityElementsHidden = true

        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        elapsedLabel.textColor = .secondaryLabel
        elapsedLabel.textAlignment = .center

        transportBar.addSubview(previousButton)
        transportBar.addSubview(elapsedLabel)
        transportBar.addSubview(playPauseButton)
        transportBar.addSubview(recenterButton)
        transportBar.addSubview(highlightsButton)
        setTransportEnabled(false)

        let size = Self.transportButtonSize
        // Kept above the home indicator in updateInnerInsets (pages live in a scroll view,
        // so the safe area is applied by hand).
        transportButtonsBottom = previousButton.bottomAnchor.constraint(
            equalTo: transportBar.bottomAnchor,
            constant: -Self.transportBarVerticalPadding
        )
        NSLayoutConstraint.activate([
            transportBar.bottomAnchor.constraint(equalTo: transcriptPage.bottomAnchor),
            transportBar.leadingAnchor.constraint(equalTo: transcriptPage.leadingAnchor),
            transportBar.trailingAnchor.constraint(equalTo: transcriptPage.trailingAnchor),
            transportBar.topAnchor.constraint(equalTo: previousButton.topAnchor, constant: -Self.transportBarVerticalPadding),

            previousButton.leadingAnchor.constraint(equalTo: transportBar.leadingAnchor, constant: Self.horizontalInset),
            transportButtonsBottom,
            previousButton.widthAnchor.constraint(equalToConstant: size),
            previousButton.heightAnchor.constraint(equalToConstant: size),

            playPauseButton.trailingAnchor.constraint(equalTo: transportBar.trailingAnchor, constant: -Self.horizontalInset),
            playPauseButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: size),
            playPauseButton.heightAnchor.constraint(equalToConstant: size),

            highlightsButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -12),
            highlightsButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            highlightsButton.widthAnchor.constraint(equalToConstant: size),
            highlightsButton.heightAnchor.constraint(equalToConstant: size),

            recenterButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 12),
            recenterButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            recenterButton.widthAnchor.constraint(equalToConstant: size),
            recenterButton.heightAnchor.constraint(equalToConstant: size),

            elapsedLabel.centerXAnchor.constraint(equalTo: transportBar.centerXAnchor),
            elapsedLabel.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
        ])
    }

    private func setTransportEnabled(_ enabled: Bool) {
        previousButton.isEnabled = enabled
        playPauseButton.isEnabled = enabled
    }

    private func updatePlayPauseButton() {
        let playing = playerView.isPlaying
        guard playing != shownPlaying else { return }
        shownPlaying = playing
        playPauseButton.setSymbol(playing ? "pause.fill" : "play.fill")
        playPauseButton.accessibilityLabel = playing ? "Pause" : "Play"
        if playing { dismissCallout(animated: true) }
    }

    // MARK: - Options menu

    private func configureOptionsMenu() {
        let menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.optionsMenuElements() ?? [])
            },
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: menu
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Options"
    }

    private func optionsMenuElements() -> [UIMenuElement] {
        let currentRate = playerView.playbackRate
        let speeds = Self.playbackRates.map { rate in
            UIAction(
                title: Self.rateTitle(rate),
                state: abs(rate - currentRate) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.playerView.setPlaybackRate(rate)
            }
        }
        let speedMenu = UIMenu(
            title: "Speed",
            subtitle: Self.rateTitle(currentRate),
            image: UIImage(systemName: "gauge.with.dots.needle.67percent"),
            children: speeds
        )
        let furigana = UIAction(
            title: "Furigana",
            image: UIImage(systemName: "textformat.size"),
            state: showsFurigana ? .on : .off
        ) { [weak self] _ in
            self?.toggleFurigana()
        }
        let loop = UIAction(
            title: "Loop clip",
            image: UIImage(systemName: "repeat"),
            state: loopsClip ? .on : .off
        ) { [weak self] _ in
            self?.loopsClip.toggle()
        }
        let english = UIAction(
            title: "English",
            image: UIImage(systemName: "character.bubble"),
            attributes: rows.contains { $0.englishLabel != nil } ? [] : .disabled,
            state: showsEnglish ? .on : .off
        ) { [weak self] _ in
            self?.toggleEnglish()
        }
        let youTubeControls = UIAction(
            title: "YouTube controls",
            image: UIImage(systemName: "slider.horizontal.below.rectangle"),
            state: playerView.showsControls ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            let shows = !self.playerView.showsControls
            Self.showsYouTubeControls = shows
            self.playerView.setShowsControls(shows)
        }
        let highlightsSheet = UIAction(
            title: "Highlights in sheet",
            image: UIImage(systemName: "rectangle.bottomthird.inset.filled"),
            state: Self.highlightsInSheet ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            Self.highlightsInSheet.toggle()
            if let payload = self.payload { self.installHighlights(payload) }
        }
        var elements: [UIMenuElement] = [
            speedMenu,
            UIMenu(options: .displayInline, children: [furigana, english, loop, youTubeControls]),
        ]
        if !isInFeed {
            elements.append(UIMenu(title: "Experiments", options: .displayInline, children: [highlightsSheet]))
        }
        if let payload {
            let start = Int(payload.media.startSec.rounded(.down))
            let url = URL(string: "https://www.youtube.com/watch?v=\(payload.media.videoID)&t=\(start)s")
            let open = UIAction(title: "Open in YouTube", image: UIImage(systemName: "arrow.up.right.square")) { _ in
                if let url { UIApplication.shared.open(url) }
            }
            elements.append(UIMenu(options: .displayInline, children: [open]))
        }
        return elements
    }

    private static func rateTitle(_ rate: Double) -> String {
        rate == 1 ? "Normal" : String(format: "%gx", rate)
    }

    // MARK: - Loading

    private func load() {
        spinner.startAnimating()
        statusLabel.text = nil
        Task { [weak self] in
            do {
                let payload = try await ContentCMSClient.fetchClip(id: self?.clipID ?? "")
                self?.apply(payload)
            } catch {
                self?.spinner.stopAnimating()
                self?.statusLabel.text = "Couldn’t load this clip.\n\(error.localizedDescription)"
            }
        }
    }

    private func apply(_ payload: ClipPayload) {
        self.payload = payload
        spinner.stopAnimating()
        // Opened without a list row (e.g. by id): show the video's title once known.
        if title == clipID, let videoTitle = payload.media.title { title = videoTitle }
        if payload.media.isPortrait != isPortraitLayout {
            applyPlayerOrientation(portrait: payload.media.isPortrait)
        }
        // A deprecated clip's video may be gone: keep the transcript (lookups,
        // breakdowns, highlights still work) but never play it.
        let playable = !payload.isDeprecated
        if playable {
            loadPlayer(videoID: payload.media.videoID, startSec: payload.media.startSec)
        } else {
            playerView.pause()
            unavailableLabel.text = "This video is no longer available.\nThe transcript is still here."
            unavailableLabel.isHidden = false
            playerView.bringSubviewToFront(unavailableLabel)
        }
        buildRows(payload)
        updateClipInfo(payload)
        // Lines fade in under the already-placed player instead of popping.
        stack.alpha = 0
        UIView.animate(withDuration: 0.25) { self.stack.alpha = 1 }
        setTransportEnabled(playable)
        guard playable else { return }
        updateElapsed(at: payload.media.startSec)
        startDisplayLink()
    }

    /// e.g. "0:42 · 8 lines · 5 vocab · 2 grammar" (highlight counts only when present).
    private func updateClipInfo(_ payload: ClipPayload) {
        var parts = [
            Self.formatTime(max(0, payload.media.endSec - payload.media.startSec)),
            Self.counted(payload.sentences.count, "line", "lines"),
        ]
        let vocabCount = payload.highlights?.vocabulary?.count ?? 0
        if vocabCount > 0 { parts.append("\(vocabCount) vocab") }
        let grammarCount = payload.highlights?.grammarPatterns?.count ?? 0
        if grammarCount > 0 { parts.append("\(grammarCount) grammar") }
        if let level = payload.jlptLevel { parts.append("N\(level)") }
        setClipInfo(parts)
    }

    private func setClipInfo(_ parts: [String]) {
        clipInfoLabel.text = parts.joined(separator: " · ")
        clipInfoLabel.accessibilityLabel = "Clip length \(parts.joined(separator: ", "))"
    }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func buildRows(_ payload: ClipPayload) {
        rows.forEach { $0.container.removeFromSuperview() }
        rows = []
        timeline = []

        var tokensBySentence: [Int: [ClipPayload.Token]] = [:]
        for token in payload.tokens.sorted(by: { $0.position < $1.position }) {
            tokensBySentence[token.sentenceIndex, default: []].append(token)
        }

        for (rowIndex, sentence) in payload.sentences.enumerated() {
            let tokens = tokensBySentence[sentence.index] ?? []
            let mapped = Self.mapTokens(tokens.map(\.surface), onto: sentence.textJP)

            let timeButton = UIButton(type: .system)
            var timeConfig = UIButton.Configuration.plain()
            timeConfig.title = Self.formatTime(sentence.startSec)
            timeConfig.contentInsets = .zero
            timeConfig.baseForegroundColor = .tertiaryLabel
            timeConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                return updated
            }
            timeButton.configuration = timeConfig
            timeButton.contentHorizontalAlignment = .leading
            timeButton.accessibilityLabel = "Play from \(Self.formatTime(sentence.startSec))"
            timeButton.addAction(UIAction { [weak self] _ in self?.playSentence(rowIndex) }, for: .primaryActionTriggered)

            let textView = LyricsInsetUnderlineTextView()
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.tintColor = .clear
            textView.isScrollEnabled = false
            textView.tokenSelectionAppearance = .definitionTip
            textView.tokenSpacing = Self.tokenSpacing
            textView.plainLineSpacing = Self.plainLineSpacing
            textView.onWordTapped = { [weak self] surface, _, tokenIndex in
                self?.wordTapped(surface: surface, tokenIndex: tokenIndex, row: rowIndex)
            }

            var englishLabel: UILabel?
            if let english = sentence.textEN?.trimmingCharacters(in: .whitespacesAndNewlines), !english.isEmpty {
                let label = UILabel()
                label.text = english
                label.font = .preferredFont(forTextStyle: .subheadline)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.numberOfLines = 0
                label.isHidden = !showsEnglish
                englishLabel = label
            }

            // The text view keeps a leading inset so readings at the line start are
            // not clipped. Let that inset hang outside the column instead of
            // indenting the Japanese past the timestamp and English.
            let textHost = UIView()
            textHost.addSubview(textView)
            let textLeading = textView.leadingAnchor.constraint(equalTo: textHost.leadingAnchor)
            NSLayoutConstraint.activate([
                textLeading,
                textView.trailingAnchor.constraint(equalTo: textHost.trailingAnchor),
                textView.topAnchor.constraint(equalTo: textHost.topAnchor),
                textView.bottomAnchor.constraint(equalTo: textHost.bottomAnchor),
            ])

            let textColumn = UIStackView(arrangedSubviews: [timeButton, textHost] + [englishLabel].compactMap { $0 })
            textColumn.axis = .vertical
            textColumn.alignment = .fill
            textColumn.spacing = 4

            let breakdownButton = UIButton(type: .system)
            var chevronConfig = UIButton.Configuration.plain()
            chevronConfig.image = UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            )
            chevronConfig.baseForegroundColor = .tertiaryLabel
            breakdownButton.configuration = chevronConfig
            breakdownButton.accessibilityLabel = "Break down this line"
            breakdownButton.translatesAutoresizingMaskIntoConstraints = false
            breakdownButton.setContentHuggingPriority(.required, for: .horizontal)
            breakdownButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            breakdownButton.addAction(UIAction { [weak self] _ in self?.openBreakdown(rowIndex) }, for: .primaryActionTriggered)
            NSLayoutConstraint.activate([
                breakdownButton.widthAnchor.constraint(equalToConstant: 44),
                breakdownButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])

            let container = UIStackView(arrangedSubviews: [textColumn, breakdownButton])
            container.axis = .horizontal
            container.alignment = .center
            container.spacing = 4
            stack.addArrangedSubview(container)

            let row = Row(
                sentence: sentence,
                container: container,
                textView: textView,
                textLeading: textLeading,
                englishLabel: englishLabel,
                tokenRanges: mapped.ranges,
                japaneseTokens: mapped.japaneseTokens
            )
            configureText(row)
            rows.append(row)

            for (tokenIndex, token) in tokens.enumerated() {
                timeline.append(TimedToken(
                    ref: TokenRef(sentence: rowIndex, token: tokenIndex),
                    start: token.startSec,
                    end: token.endSec
                ))
            }
        }
        timeline.sort { $0.start < $1.start }
        activeToken = nil
        activeSentence = nil
        captionToken = nil
        updateCaptionOverlay()
        updateRowEmphasis()
        installHighlights(payload)
    }

    // MARK: - Highlights

    /// Shows the highlights page (second pager page) when the clip has highlights.
    private func installHighlights(_ payload: ClipPayload) {
        let highlights = payload.learningHighlights
        let hasHighlights = !highlights.isEmpty
        let usesSheet = Self.highlightsInSheet || isInFeed
        hasHighlightsPage = hasHighlights && !usesSheet
        highlightsButton.isHidden = !(hasHighlights && usesSheet)
        if hasHighlightsPage {
            highlightsView.configure(highlights: highlights)
        }
        highlightsPage.isHidden = !hasHighlightsPage
        highlightsPageHeight.isActive = hasHighlightsPage
        view.layoutIfNeeded()
        if !hasHighlightsPage, activePage != 0 {
            handoffCoordinator?.settleOnPage(0)
            pageDidChange(to: 0)
        }
        updateInnerInsets()
        updateSeamChevron()
    }

    private func presentHighlightsSheet() {
        guard let payload, presentedViewController == nil else { return }
        dismissCallout(animated: false)
        playerView.pause()
        let sheet = ClipHighlightsSheetViewController(highlights: payload.learningHighlights)
        sheet.onSelectVocabulary = { [weak self, weak sheet] word in
            guard let self, let sheet else { return }
            // Layer the dictionary over the highlights so closing it returns there.
            let sentence = self.rows.first { $0.sentence.textJP.contains(word) }?.sentence
            WordDictionaryDetailSheetPresenter.present(
                surface: word,
                sentence: sentence?.textJP,
                glossFraming: .word,
                lineEnglish: sentence?.textEN,
                from: sheet
            )
        }
        sheet.onSelectGrammar = { [weak self, weak sheet] pattern in
            // Pushes inside the sheet's own navigation controller.
            guard let self, let sheet else { return }
            self.presentGrammar(pattern, from: sheet)
        }
        let nav = UINavigationController(rootViewController: sheet)
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func presentVocabulary(_ word: String) {
        dismissCallout(animated: false)
        // Context: the first line that contains the word, when there is one.
        let sentence = rows.first { $0.sentence.textJP.contains(word) }?.sentence
        playerView.pause()
        WordDictionaryDetailSheetPresenter.present(
            surface: word,
            sentence: sentence?.textJP,
            glossFraming: .word,
            lineEnglish: sentence?.textEN,
            from: self
        )
    }

    private func presentGrammar(_ pattern: DialogueGrammarPatternRef, from presenter: UIViewController? = nil) {
        guard let payload else { return }
        dismissCallout(animated: false)
        playerView.pause()
        let lines = payload.scenarioLines
        GrammarPatternDetailPresenter.push(
            pattern: pattern,
            catalogPattern: payload.teachingPattern(for: pattern),
            spokenLines: lines,
            request: GeminiGrammarUsage.request(for: pattern, in: lines),
            from: presenter ?? self
        )
    }

    private func configureText(_ row: Row) {
        if let japaneseTokens = row.japaneseTokens {
            row.textView.configure(
                sentence: row.sentence.textJP,
                lyricFont: lyricFont,
                japaneseTokens: japaneseTokens,
                showsFurigana: showsFurigana
            )
        } else {
            row.textView.configure(
                sentence: row.sentence.textJP,
                lyricFont: lyricFont,
                showsFurigana: showsFurigana
            )
        }
        // The inset depends on font size and furigana, so refresh it every time.
        row.textLeading.constant = -row.textView.textContainerInset.left
    }

    /// Surfaces located left to right in `text` (same rule as DialogueTokenSync).
    private static func mapTokens(
        _ surfaces: [String],
        onto text: String
    ) -> (ranges: [NSRange?], japaneseTokens: [JapaneseToken]?) {
        var searchStart = text.startIndex
        var ranges: [NSRange?] = []
        var japaneseTokens: [JapaneseToken] = []
        var complete = !surfaces.isEmpty
        for surface in surfaces {
            let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let range = text.range(of: trimmed, range: searchStart..<text.endIndex) else {
                ranges.append(nil)
                complete = false
                continue
            }
            ranges.append(NSRange(range, in: text))
            japaneseTokens.append(JapaneseToken(text: trimmed, range: range))
            searchStart = range.upperBound
        }
        return (ranges, complete ? japaneseTokens : nil)
    }

    // MARK: - Player

    private func configurePlayerCallbacks() {
        playerView.onStateChange = { [weak self] _ in
            self?.updatePlayPauseButton()
        }
        playerView.onError = { [weak self] code in
            guard let self else { return }
            let reason: String
            switch code {
            case 101, 150: reason = "The owner doesn’t allow this video to be embedded."
            case 100: reason = "This video is private or was removed."
            default: reason = "YouTube player error \(code)."
            }
            self.statusLabel.text = reason
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil, let payload, !payload.isDeprecated, view.window != nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick() {
        guard let payload, playerView.isReady else { return }
        let time = playerView.currentTime
        if playerView.isPlaying,
           time >= payload.media.endSec,
           CACurrentMediaTime() - lastLoopSeekTime > 1 {
            lastLoopSeekTime = CACurrentMediaTime()
            if loopsClip {
                playerView.seek(to: payload.media.startSec)
            } else {
                playerView.pause()
                playerView.seek(to: payload.media.startSec)
            }
            return
        }
        updateElapsed(at: time)
        updateHighlight(at: time)
    }

    private func updateElapsed(at time: TimeInterval) {
        guard let payload else { return }
        let elapsed = max(0, Int((time - payload.media.startSec).rounded(.down)))
        guard elapsed != lastElapsedSecond else { return }
        lastElapsedSecond = elapsed
        let total = max(0, payload.media.endSec - payload.media.startSec)
        elapsedLabel.text = "\(Self.formatTime(TimeInterval(elapsed))) / \(Self.formatTime(total))"
    }

    // MARK: - Highlight

    private func updateHighlight(at time: TimeInterval) {
        // Last token that has started.
        var low = 0
        var high = timeline.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if timeline[mid].start <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let nextToken: TokenRef?
        if let found, time < timeline[found].end + Self.highlightHoldSeconds {
            nextToken = timeline[found].ref
        } else {
            nextToken = nil
        }
        let nextSentence = found.map { timeline[$0].ref.sentence }

        // The caption keeps its line through short gaps, then clears until the next one.
        let nextCaptionToken = found.map { timeline[$0].ref }.flatMap { ref -> TokenRef? in
            guard rows.indices.contains(ref.sentence),
                  time < rows[ref.sentence].sentence.endSec + Self.captionHoldSeconds else { return nil }
            return ref
        }
        let tokenChanged = nextToken != activeToken
        if tokenChanged {
            if let previous = activeToken, previous.sentence != nextToken?.sentence {
                setKaraoke(row: previous.sentence, range: nil)
            }
            if let nextToken {
                let row = rows[nextToken.sentence]
                let range = row.tokenRanges.indices.contains(nextToken.token)
                    ? row.tokenRanges[nextToken.token]
                    : nil
                setKaraoke(row: nextToken.sentence, range: range)
            }
            activeToken = nextToken
        }

        if tokenChanged || nextCaptionToken != captionToken {
            captionToken = nextCaptionToken
            updateCaptionOverlay()
        }

        if nextSentence != activeSentence {
            activeSentence = nextSentence
            updateRowEmphasis()
            if let nextSentence { autoScroll(toRow: nextSentence) }
        } else if tokenChanged, let nextToken {
            // Same line, next word: follow the marker as the line wraps.
            followKaraokeLine(row: nextToken.sentence)
        }
    }

    /// Long lines wrap past the visible transcript. Once the marker's wrapped line
    /// sinks below the upper part of the view, scroll so it sits one line under
    /// the top (the previous wrapped line stays for context).
    private func followKaraokeLine(row index: Int) {
        guard rows.indices.contains(index),
              activePage == 0,
              handoffCoordinator?.isAnimatingPageSnap != true,
              !isUserScrolling,
              isFollowingPlayback,
              CACurrentMediaTime() - lastAutoScrollTime > Self.wrapFollowSettleSeconds,
              let line = rows[index].textView.karaokeLineFragmentRectsInTextView().first else { return }
        let lineFrame = rows[index].textView.convert(line, to: scrollView)
        let inset = scrollView.adjustedContentInset
        let visibleTop = scrollView.contentOffset.y + inset.top
        let visibleHeight = scrollView.bounds.height - inset.top - inset.bottom
        guard visibleHeight > 0 else { return }
        let comfortable = lineFrame.minY >= visibleTop
            && lineFrame.maxY <= visibleTop + visibleHeight * Self.wrapFollowThreshold
        guard !comfortable else { return }
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let target = min(maxY, max(minY, lineFrame.minY - lineFrame.height - inset.top - 12))
        guard abs(target - scrollView.contentOffset.y) > 1 else { return }
        lastAutoScrollTime = CACurrentMediaTime()
        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    private func setKaraoke(row index: Int, range: NSRange?) {
        guard rows.indices.contains(index) else { return }
        let textView = rows[index].textView
        let displayRange = range.flatMap {
            DialogueContentLineWrap.mapOriginalUTF16Range($0, onto: textView.displayedString)
        }
        textView.setKaraokeHighlight(
            range: displayRange,
            fullHeight: true,
            highlightColor: FuriganaTranscriptLabel.tokenSyncHighlightColor
        )
    }

    /// Lines already reached stay full strength; only lines not spoken yet are grayed.
    private func updateRowEmphasis() {
        for (index, row) in rows.enumerated() {
            let spoken = activeSentence.map { index <= $0 } ?? false
            row.container.alpha = spoken ? 1 : 0.45
        }
    }

    /// Parks the active line just below the transport bar.
    private func autoScroll(toRow index: Int) {
        guard rows.indices.contains(index),
              activePage == 0,
              handoffCoordinator?.isAnimatingPageSnap != true,
              !isUserScrolling,
              isFollowingPlayback else { return }
        view.layoutIfNeeded()
        let rowFrame = rows[index].container.convert(rows[index].container.bounds, to: scrollView)
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let target = min(maxY, max(minY, rowFrame.minY - inset.top - 12))
        lastAutoScrollTime = CACurrentMediaTime()
        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    // MARK: - Follow playback

    private func setFollowingPlayback(_ following: Bool) {
        guard following != isFollowingPlayback else { return }
        isFollowingPlayback = following
        recenterButton.isUserInteractionEnabled = !following
        recenterButton.accessibilityElementsHidden = following
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.recenterButton.alpha = following ? 0 : 1
            self.recenterButton.transform = following ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
        }
    }

    /// Back to following the spoken line; `scroll` jumps there now instead of at the next line.
    private func resumeFollowingPlayback(scroll: Bool) {
        setFollowingPlayback(true)
        guard scroll else { return }
        autoScroll(toRow: activeSentence ?? 0)
    }

    // MARK: - Transport actions

    private func playPauseTapped() {
        if playerView.isPlaying {
            playerView.pause()
        } else {
            playerView.play()
        }
    }

    /// Restart the current line; near its start, jump to the line before.
    private func previousTapped() {
        guard !rows.isEmpty else { return }
        let time = playerView.currentTime
        let current = activeSentence ?? 0
        var target = current
        if rows.indices.contains(current),
           time - rows[current].sentence.startSec < Self.previousLineGraceSeconds {
            target = max(0, current - 1)
        }
        resumeFollowingPlayback(scroll: false)
        playSentence(target)
    }

    private func playSentence(_ index: Int) {
        guard let payload, !payload.isDeprecated, rows.indices.contains(index) else { return }
        resumeFollowingPlayback(scroll: false)
        let start = max(payload.media.startSec, rows[index].sentence.startSec - Self.replayLeadInSeconds)
        playerView.seek(to: start)
        playerView.play()
    }

    private func toggleFurigana() {
        dismissCallout(animated: false)
        showsFurigana.toggle()
        rows.forEach(configureText)
        // Reconfiguring drops the karaoke marker; re-apply on the next tick.
        activeToken = nil
    }

    private func toggleEnglish() {
        showsEnglish.toggle()
        updateCaptionOverlay()
        UIView.animate(withDuration: 0.2) {
            for row in self.rows {
                row.englishLabel?.isHidden = !self.showsEnglish
                row.englishLabel?.alpha = self.showsEnglish ? 1 : 0
            }
            self.stack.layoutIfNeeded()
        }
    }

    // MARK: - Breakdown

    /// Sentence scrub for one line, with neighboring lines as nuance context.
    private func openBreakdown(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        dismissCallout(animated: false)
        playerView.pause()
        let row = rows[index]
        let lines = rows.map {
            DialogueNuanceContext.Line(speaker: "", japanese: $0.sentence.textJP, english: $0.sentence.textEN)
        }
        let scrub = SentenceScrubExperimentViewController(
            sentence: row.sentence.textJP,
            englishTranslation: row.sentence.textEN,
            dialogueContext: DialogueNuanceContext.around(lines: lines, focusedIndex: index),
            tokens: row.japaneseTokens
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    // MARK: - Definition callout

    /// First tap: pause and show the rich callout (reading, dictionary form, part of speech,
    /// first senses) over the word. Tapping it opens the full dictionary sheet.
    private func wordTapped(surface: String, tokenIndex: Int, row rowIndex: Int) {
        guard rows.indices.contains(rowIndex) else { return }
        let ref = TokenRef(sentence: rowIndex, token: tokenIndex)
        if calloutToken == ref {
            dismissCallout(animated: true)
            return
        }
        playerView.pause()

        let row = rows[rowIndex]
        let fragments = row.textView.mergedWordLineFragmentRectsInTextView(forTokenIndex: tokenIndex)
        guard !fragments.isEmpty else {
            presentDictionary(surface: surface, sentence: row.sentence)
            return
        }
        if let previous = calloutToken, previous.sentence != rowIndex, rows.indices.contains(previous.sentence) {
            rows[previous.sentence].textView.setDefinitionSelectionHighlight(tokenIndex: nil)
        }
        calloutToken = ref
        row.textView.setDefinitionSelectionHighlight(tokenIndex: tokenIndex)

        DefinitionCalloutPresenter.shared.presentOrUpdate(
            content: .jmdict(surface: surface, sentence: row.sentence.textJP),
            surface: surface,
            lineFragments: fragments,
            in: row.textView,
            gap: Self.calloutGap,
            onLongPress: flagHandler(sentence: row.sentence.textJP)
        ) { [weak self] surface in
            guard let self else { return }
            self.dismissCallout(animated: true)
            self.presentDictionary(surface: surface, sentence: row.sentence)
        }
    }

    /// Debug builds: press and hold the callout to flag a missing or wrong definition for
    /// Settings → Dictionary checks. Only a haptic and a VoiceOver announcement confirm it.
    private func flagHandler(sentence: String) -> ((String) -> Void)? {
        #if DEBUG
        return { [weak self] surface in
            DictionaryFlagStore.shared.flag(surface: surface, sentence: sentence, source: self?.title)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: "Flagged \(surface)")
        }
        #else
        return nil
        #endif
    }

    private func dismissCallout(animated: Bool) {
        guard let token = calloutToken else { return }
        calloutToken = nil
        if rows.indices.contains(token.sentence) {
            rows[token.sentence].textView.setDefinitionSelectionHighlight(tokenIndex: nil)
        }
        DefinitionCalloutPresenter.shared.dismiss(animated: animated)
    }

    /// The sheet keeps the tapped token (聞きました) as the headword, names its form,
    /// and lists the dictionary form (聞く) under it.
    private func presentDictionary(surface: String, sentence: ClipPayload.Sentence) {
        playerView.pause()
        WordDictionaryDetailSheetPresenter.present(
            surface: surface,
            sentence: sentence.textJP,
            lineEnglish: sentence.textEN,
            keepsTappedFormAsHeadword: true,
            from: self
        )
    }

    /// Taps on empty space close the callout; words and buttons handle their own taps.
    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        dismissCallout(animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === feedSwipePan else { return true }
        let velocity = feedSwipePan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === feedSwipePan
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === feedSwipePan { return true }
        guard calloutToken != nil else { return false }
        var view = touch.view
        while let current = view {
            if current is LyricsInsetUnderlineTextView || current is UIControl { return false }
            view = current.superview
        }
        return !DefinitionCalloutPresenter.shared.isShowingCallout(at: touch.location(in: self.view), in: self.view)
    }

    // MARK: - UIScrollViewDelegate

    // Inner scroll views report through the handoff coordinator's forwardingDelegate.

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === outerScrollView { updateSeamChevron() }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dismissCallout(animated: true)
        guard scrollView === self.scrollView else { return }
        isUserScrolling = true
        setFollowingPlayback(false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === self.scrollView else { return }
        if !decelerate { endUserScroll() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        endUserScroll()
    }

    private func endUserScroll() {
        isUserScrolling = false
    }

    // MARK: - Formatting

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Grabber under the Shorts player: drag between detents, or VoiceOver swipe up/down.
private final class ClipPlayerResizeHandle: UIView {
    /// +1 = taller, -1 = shorter (VoiceOver adjustable).
    var onAdjust: ((CGFloat) -> Void)?
    private let grabber = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous
        addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.centerYAnchor.constraint(equalTo: centerYAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Resize video"
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setActive(_ active: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.grabber.backgroundColor = active ? .secondaryLabel : .tertiaryLabel
            self.grabber.transform = active ? CGAffineTransform(scaleX: 1.25, y: 1.2) : .identity
        }
    }

    override func accessibilityIncrement() { onAdjust?(1) }
    override func accessibilityDecrement() { onAdjust?(-1) }

    /// Taller touch target than the visible 22 pt band.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -10).contains(point)
    }
}

/// Captions over the bottom of the Shorts player: a progressive blur (clear at
/// the top, strongest under the text) with a light scrim, the spoken line
/// (words said so far at full strength, the rest dimmed), and its English.
/// Display only; it stands in for the transcript, which is hidden while the
/// player is at the full detent.
private final class ClipCaptionOverlayView: UIView {
    private static let spokenColor = UIColor.white
    private static let unspokenColor = UIColor.white.withAlphaComponent(0.55)

    private let blur = ClipProgressiveBlurView(style: .systemUltraThinMaterialDark, steps: 4)
    private let scrim = ClipGradientView()
    private let japaneseLabel = UILabel()
    private let englishLabel = UILabel()
    private let japaneseFont = UIFont.systemFont(ofSize: 19, weight: .semibold)
    private var shown: (japanese: String?, spokenLength: Int, english: String?) = (nil, 0, nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true

        scrim.gradient.colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.3).cgColor]
        scrim.gradient.locations = [0, 1]
        [blur, scrim].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: topAnchor),
                $0.leadingAnchor.constraint(equalTo: leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: trailingAnchor),
                $0.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        japaneseLabel.font = japaneseFont
        japaneseLabel.numberOfLines = 0
        englishLabel.font = .systemFont(ofSize: 13, weight: .medium)
        englishLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        englishLabel.numberOfLines = 2
        for label in [japaneseLabel, englishLabel] {
            label.textAlignment = .center
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.35
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = .zero
        }

        let textStack = UIStackView(arrangedSubviews: [japaneseLabel, englishLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            // Room above the text for the blur to ramp up.
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 28),
        ])
        setLine(japanese: nil, spokenLength: 0, english: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `spokenLength` is a UTF-16 prefix of `japanese` drawn at full strength.
    func setLine(japanese: String?, spokenLength: Int, english: String?) {
        let english = english?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard shown.japanese != japanese
            || shown.spokenLength != spokenLength
            || shown.english != english else { return }
        shown = (japanese, spokenLength, english)

        guard let japanese else {
            japaneseLabel.attributedText = nil
            japaneseLabel.isHidden = true
            englishLabel.text = nil
            englishLabel.isHidden = true
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        let text = NSMutableAttributedString(
            string: japanese,
            attributes: [.font: japaneseFont, .foregroundColor: Self.unspokenColor, .paragraphStyle: paragraph]
        )
        let spoken = min(max(spokenLength, 0), text.length)
        if spoken > 0 {
            text.addAttribute(.foregroundColor, value: Self.spokenColor, range: NSRange(location: 0, length: spoken))
        }
        japaneseLabel.attributedText = text
        japaneseLabel.isHidden = false
        englishLabel.text = english
        englishLabel.isHidden = english == nil
    }
}

private final class ClipGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

/// Blur that grows stronger toward the bottom, built from public API: stacked
/// blur bands, each masked to fade in a little lower than the last, so the
/// bottom is blurred by every band and the top by none.
private final class ClipProgressiveBlurView: UIView {
    private var bands: [(effect: UIVisualEffectView, mask: ClipGradientView)] = []

    init(style: UIBlurEffect.Style, steps: Int) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let count = max(1, steps)
        for step in 0..<count {
            let effect = UIVisualEffectView(effect: UIBlurEffect(style: style))
            effect.frame = bounds
            effect.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let mask = ClipGradientView()
            // Band n ramps from clear to full over 30% of the height, starting n/count of the way into the top 70%.
            let start = CGFloat(step) / CGFloat(count) * 0.7
            mask.gradient.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
            mask.gradient.locations = [NSNumber(value: Double(start)), NSNumber(value: Double(min(1, start + 0.3)))]
            effect.mask = mask
            addSubview(effect)
            bands.append((effect, mask))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for band in bands {
            band.mask.frame = band.effect.bounds
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Hosts the info row's edge effect: its subviews (the resize grabber) take
/// touches, and empty space passes them through to the transcript underneath.
/// Fades its content in over the top `fadeHeight` points (clear at the edge, opaque below).
private final class ClipTopFadeView: UIView {
    var fadeHeight: CGFloat = 20 {
        didSet { setNeedsLayout() }
    }
    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        fadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        layer.mask = fadeMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Runs past the bottom so a spring-animated resize never clips the
        // transcript's bottom before the frame catches up.
        let height = bounds.height + 1000
        CATransaction.begin()
        // Follow the frame during animated resizes instead of lagging behind with an implicit animation.
        CATransaction.setDisableActions(true)
        fadeMask.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        fadeMask.locations = [0, NSNumber(value: Double(min(fadeHeight / height, 1)))]
        CATransaction.commit()
    }
}

private final class ClipPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// CADisplayLink retains its target; this keeps the controller releasable.
private final class DisplayLinkProxy: NSObject {
    weak var target: ClipPlayerViewController?

    init(_ target: ClipPlayerViewController) {
        self.target = target
    }

    @objc func tick() {
        target?.tick()
    }
}


/// Experiment: the clip's VOCAB / GRAMMAR / notes in a bottom sheet.
private final class ClipHighlightsSheetViewController: UIViewController {
    var onSelectVocabulary: ((String) -> Void)?
    var onSelectGrammar: ((DialogueGrammarPatternRef) -> Void)?

    private let highlights: DialogueLearningHighlights
    private let scrollView = UIScrollView()
    private let content = DialogueLearningHighlightsContentView()

    init(highlights: DialogueLearningHighlights) {
        self.highlights = highlights
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        title = "Highlights"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        content.translatesAutoresizingMaskIntoConstraints = false
        content.configure(highlights: highlights)
        content.onSelectVocabulary = { [weak self] in self?.onSelectVocabulary?($0) }
        content.onSelectGrammar = { [weak self] in self?.onSelectGrammar?($0) }
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }
}
