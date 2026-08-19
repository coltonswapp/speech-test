//
//  DialogueExperimentViewController.swift
//  shizen
//
//  Scrollable furigana dialogue transcript in a medium/large sheet with
//  bundled scenario audio and active-line follow-along emphasis.
//

import AVFoundation
import TTSCore
import UIKit

// MARK: - Debug fixture

enum DialogueExperimentFixture {

    static let audioKey = "n5-cha-ikenai/dialogue-8-lines"
    static let pointID = "n5-cha-ikenai"

    static func loadExample() -> (pointTitle: String, example: GrammarExample) {
        if let point = GrammarCurriculum.point(id: pointID),
           let example = point.examples.first(where: { $0.audioKey == audioKey }) {
            return (point.title, example)
        }
        return (fallbackPointTitle, fallbackExample)
    }

    private static let fallbackPointTitle = "ちゃいけない・じゃいけない"

    private static let fallbackExample = GrammarExample(
        japanese: "本を返す前にゴミも捨てちゃいけないからね。",
        romaji: "hon o kaesu mae ni gomi mo sutecha ikenai kara ne.",
        english: "You have to throw away your trash before returning your books.",
        targetSubstring: "捨てちゃいけない",
        audioKey: audioKey,
        publishedAudioUrl: nil,
        scenario: GrammarScenario(
            setting: "After school — two friends study at the library.",
            lines: [
                GrammarScenarioLine(
                    speaker: "Yui",
                    japanese: "ねえ、まだ宿題ある？",
                    romaji: "nee, mada shukudai aru?",
                    english: "Hey, do you still have homework?"
                ),
                GrammarScenarioLine(
                    speaker: "Ken",
                    japanese: "うん、数学と英語。結構残ってる。",
                    romaji: "un, suugaku to eigo. kekkou nokotteru.",
                    english: "Yeah — math and English. Quite a bit left."
                ),
                GrammarScenarioLine(
                    speaker: "Yui",
                    japanese: "大変だね。ここでやっていい？",
                    romaji: "taihen da ne. koko de yatte ii?",
                    english: "That's rough. Is it okay to work here?"
                ),
                GrammarScenarioLine(
                    speaker: "Ken",
                    japanese: "うん、静かだし。でも飲み物は外に置いときなよ。",
                    romaji: "un, shizuka da shi. demo nomimono wa soto ni oito ki na yo.",
                    english: "Sure, it's quiet. But keep your drinks outside."
                ),
                GrammarScenarioLine(
                    speaker: "Yui",
                    japanese: "あ、コップ持ってきちゃった。",
                    romaji: "a, koppu motte kichatta.",
                    english: "Oh — I brought my cup in."
                ),
                GrammarScenarioLine(
                    speaker: "Ken",
                    japanese: "図書館では食べ物も飲み物も持ち込んじゃダメだよ。",
                    romaji: "toshokan de wa tabemono mo nomimono mo mochikomu ja dame da yo.",
                    english: "You can't bring food or drinks into the library."
                ),
                GrammarScenarioLine(
                    speaker: "Yui",
                    japanese: "ごめん、今から片付ける。",
                    romaji: "gomen, ima kara katazukeru.",
                    english: "Sorry — I'll put it away now."
                ),
                GrammarScenarioLine(
                    speaker: "Ken",
                    japanese: "本を返す前にゴミも捨てちゃいけないからね。",
                    romaji: "hon o kaesu mae ni gomi mo sutecha ikenai kara ne.",
                    english: "You have to throw away your trash before returning your books."
                ),
            ]
        ),
        sourceScenarioId: nil
    )
}

// MARK: - Display model

private enum DialogueSpeakerSide {
    case leading
    case trailing
}

private struct DialogueLineDisplay {
    let speaker: String
    let speakerSide: DialogueSpeakerSide
    let showsSpeakerLabel: Bool
    let japanese: String
    let english: String?
}

private enum DialoguePlaybackPhase {
    case idle
    case playing
    case paused
    case finished
}

private enum FollowAlongScrollDirection {
    case up
    case down
}

enum DialoguePresentationContext {
    case standalone
    case nestedPagingHost
}

/// How the transcript renders its lines.
enum DialogueTranscriptDisplayMode {
    /// Japanese bubbles with English translations.
    case full
    /// Japanese bubbles only; English translations hidden.
    case japaneseOnly
    /// Listening mode: one static bubble per speaker holding a live meter.
    case listeningSpeakers
    /// Listening mode: normal transcript layout, but every line's bubble
    /// holds a live meter instead of text.
    case listeningLines
    /// Progressive reveal per line: live meter → Japanese → English.
    case reveal
}

private enum DialogueLineRevealLevel {
    case audioOnly
    case japanese
    case english
}

/// Direction along the reveal ladder. Reverses at each end so swipes cycle
/// meter → Japanese → English → Japanese → meter → …
private enum DialogueLineRevealTravel {
    case revealing
    case concealing
}

// MARK: - View controller

final class DialogueExperimentViewController: UIViewController {

    private var pointTitle: String
    private var example: GrammarExample
    private var scenarioID: String?
    private var grammarPointIDs: [String]
    private let presentationContext: DialoguePresentationContext
    private var displayLines: [DialogueLineDisplay]
    private var spokenLineTexts: [String]

    private let scrollHeaderStack = UIStackView()
    private let sceneImageContainer = UIView()
    private let sceneImageView = UIImageView()
    private let sceneImageLoadingPlaceholder = ImageLoadingPlaceholderView()
    /// Pins the scene image to ~92% of the header-stack width. Activated only
    /// once the container has been added to the stack (shared ancestor), else
    /// AutoLayout traps with a "no common ancestor" exception.
    private var sceneImageWidthConstraint: NSLayoutConstraint?
    private let settingLabel = UILabel()
    private let metadataLabel = UILabel()

    /// Asset-catalog image shown above the transcript, scrolling with content.
    /// Set before the view loads (or it is applied on the next header rebuild).
    var sceneImageName: String?
    /// Prefer CDN thumbnail when the lesson was loaded from the CMS.
    var sceneImageURL: URL?

    /// Hosts set this false for quiz-backed scenarios, where completion is
    /// earned by passing the quiz instead of finishing playback.
    var recordsCompletionOnPlaybackFinish = true

    /// Transcript rendering mode; listening variants replace text with
    /// speaker-tinted live meters. See ``DialogueTranscriptDisplayMode``.
    var transcriptDisplayMode: DialogueTranscriptDisplayMode = .full {
        didSet {
            guard transcriptDisplayMode != oldValue, isViewLoaded else { return }
            updateSceneImageWidthForCurrentMode()
            rebuildTranscriptRows()
            resetScrollPositionForNewTranscript()
        }
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var contentStackTopConstraint: NSLayoutConstraint!
    private var lineRows: [UIView] = []
    private var japaneseBubbles: [DialogueJapaneseBubbleView] = []
    private var japaneseLabels: [FuriganaTranscriptLabel] = []
    private var englishLabels: [UILabel] = []
    /// One bubble+meter per speaker in `.listeningSpeakers` mode; empty otherwise.
    private var listeningSpeakerSlots: [ListeningSpeakerSlot] = []
    /// One meter per line in `.listeningLines` / `.reveal` modes; empty otherwise.
    private var listeningLineMeters: [AudioLevelBarsView] = []
    /// Slow-tracking level baseline; the gap between the live level and this
    /// baseline marks syllable onsets for the listening meters.
    private var listeningMeterBaseline: Float = 0
    /// Per-line reveal ladder in `.reveal` mode; empty otherwise.
    private var lineRevealLevels: [DialogueLineRevealLevel] = []
    /// Per-line travel direction for cycling the reveal ladder.
    private var lineRevealTravels: [DialogueLineRevealTravel] = []
    /// UI handles for animating meter → Japanese → English in `.reveal` mode.
    private var lineRevealSlots: [LineRevealSlot] = []

    private struct ListeningSpeakerSlot {
        let speaker: String
        let side: DialogueSpeakerSide
        let bubble: DialogueJapaneseBubbleView
        let meter: AudioLevelBarsView
    }

    private struct LineRevealSlot {
        let meter: AudioLevelBarsView
        /// Edge pins that make the bubble size to the meter (audio-only).
        let meterBubbleSizingConstraints: [NSLayoutConstraint]
        /// Keeps the meter laid out (centered, fixed size) while Japanese text owns the bubble.
        let meterParkConstraints: [NSLayoutConstraint]
        let englishWrapper: UIView?
        var textMinWidthConstraint: NSLayoutConstraint?
    }

    private var bubbleMinWidthConstraints: [NSLayoutConstraint] = []
    private var appliedBubbleMinWidthColumnWidth: CGFloat = -1
    private var bubbleSwipeContainers: [DialogueBubbleSwipeRevealContainer] = []
    private var messageColumnLayouts: [LineMessageColumnLayout] = []
    private let lineChangeHaptic = UIImpactFeedbackGenerator(style: .light)

    private struct LineMessageColumnLayout {
        let column: UIStackView
        let viewBeforeBubble: UIView
        let bubbleView: UIView
        var hasEnglish: Bool
    }

    private let transportBarContainer = UIView()
    private let elapsedLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let playGlyphView = UIImageView()
    private let speedButton = UIButton(type: .system)
    private let speedGlyphView = UIImageView()
    private let restartButton = UIButton(type: .system)
    private let restartGlyphView = UIImageView()
    private let leftTransportControlsStack = UIStackView()
    private var transportBarPositionConstraints: [NSLayoutConstraint] = []

    private var playbackSpeed: Float = 1.0
    private static let playbackSpeedOptions: [Float] = [0.8, 1.0, 1.2, 1.4]

    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    private let bottomScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()

    private var audioPlayer: AVAudioPlayer?
    private var resolvedAudioURL: URL?
    private var alignedLines: [AlignedTimeLine] = []
    private var clipDuration: TimeInterval = 0
    private var progressDisplayLink: CADisplayLink?
    private var playbackPhase: DialoguePlaybackPhase = .idle
    private var activeLineIndex: Int?
    private var lineEmphasis: [CGFloat] = []
    private var emphasisAnimationLink: CADisplayLink?
    private var emphasisAnimationStart: [CGFloat] = []
    private var emphasisAnimationTarget: [CGFloat] = []
    private var emphasisAnimationStartTime: CFTimeInterval = 0
    private var followAlongScrollDirection: FollowAlongScrollDirection?
    private var followAlongScrollStartY: CGFloat = 0
    /// Emphasis value each row's message-column spacing was last set from; `setCustomSpacing`
    /// dirties the whole stack view's layout regardless of whether the value actually moved, so
    /// unchanged rows are skipped to avoid forcing a full-window layout pass every animation frame.
    private var appliedRowSpacingEmphasis: [CGFloat] = []
    private var seekTargetLineIndex: Int?
    private var playbackResumeStartedAt: CFTimeInterval = 0
    /// Invalidates in-flight async audio-session activations when a newer play
    /// request supersedes them; only the latest completion may start the player.
    private var playbackActivationGeneration = 0
    private var nestedPagingTopContentInset: CGFloat = 0
    private var nestedPagingTransportProgress: CGFloat = 0
    /// Set by `DialogueExperimentHarnessViewController` to print alignment / switch diagnostics.
    var alignmentDebugLog: ((String) -> Void)?

    /// Scroll view used for nested vertical paging handoff when embedded in a pager host.
    var handoffScrollView: UIScrollView { scrollView }

    /// Transport bar reparented onto the pager host so slide animations are not clipped by page bounds.
    var nestedPagingTransportBarView: UIView { transportBarContainer }

    init(
        pointTitle: String,
        example: GrammarExample,
        presentationContext: DialoguePresentationContext = .standalone,
        scenarioID: String? = nil,
        grammarPointIDs: [String] = []
    ) {
        self.pointTitle = pointTitle
        self.example = example
        self.scenarioID = scenarioID
        self.grammarPointIDs = grammarPointIDs
        self.presentationContext = presentationContext
        self.displayLines = Self.makeDisplayLines(for: example)
        self.spokenLineTexts = GrammarExampleDialogueLines.lines(for: example)
        super.init(nibName: nil, bundle: nil)
        title = "Scenario"
    }

    convenience init(presentationContext: DialoguePresentationContext = .standalone) {
        let fixture = DialogueExperimentFixture.loadExample()
        self.init(
            pointTitle: fixture.pointTitle,
            example: fixture.example,
            presentationContext: presentationContext
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = presentationContext == .nestedPagingHost
            ? ExperimentPalette.pageBackground
            : .systemBackground

        configureScrollContentHeader()
        configureScrollView()
        configureTransportBar()
        rebuildTranscriptRows()
        resolveLessonAudio()

        bottomScrollEdgeInteraction.scrollView = scrollView
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false

        if presentationContext == .standalone {
            attachTopScrollEdgeInteraction()
            view.bringSubviewToFront(transportBarContainer)
        }

        updateTransportControls()
        if presentationContext == .standalone {
            updateElapsedLabel(currentTime: 0)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playPauseButton.bringSubviewToFront(playGlyphView)
        speedButton.bringSubviewToFront(speedGlyphView)
        restartButton.bringSubviewToFront(restartGlyphView)
        contentStackTopConstraint.constant = 8
        applyScrollContentInsets()
        updateBubbleMinWidths()
        applyRowStylesFromEmphasis()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopEmphasisAnimation()
        if presentationContext == .standalone {
            navigationController?.navigationBar.removeInteraction(topScrollEdgeInteraction)
        }
        if isBeingDismissed || isMovingFromParent {
            stopPlayback(resetPosition: false)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if presentationContext == .nestedPagingHost {
            DialogueBubbleSwipeRevealContainer.resetCommittedContainer(animated: false)
            wireBubbleSwipeContentPopDeferral()
        }
        guard presentationContext == .standalone else { return }
        if topScrollEdgeInteraction.scrollView == nil {
            topScrollEdgeInteraction.scrollView = scrollView
        }
        if let navigationBar = navigationController?.navigationBar,
           !navigationBar.interactions.contains(where: { $0 === topScrollEdgeInteraction }) {
            navigationBar.addInteraction(topScrollEdgeInteraction)
        }
    }

    func applyNestedPagingTopContentInset(_ inset: CGFloat) {
        guard presentationContext == .nestedPagingHost else { return }
        nestedPagingTopContentInset = inset
        applyScrollContentInsets()
    }

    func applyNestedPagingTransportProgress(_ progress: CGFloat, animated: Bool = false) {
        guard presentationContext == .nestedPagingHost else { return }
        let clamped = min(max(progress, 0), 1)
        nestedPagingTransportProgress = clamped

        let applyTransforms = {
            let distance = Self.nestedPagingTransportSlideDistance * clamped
            self.transportBarContainer.transform = .identity
            self.leftTransportControlsStack.transform = CGAffineTransform(translationX: -distance, y: 0)
            self.playPauseButton.transform = CGAffineTransform(translationX: distance, y: 0)
            self.transportBarContainer.alpha = 1 - clamped
            self.transportBarContainer.isUserInteractionEnabled = clamped < 0.98
        }

        if animated {
            UIView.animate(
                withDuration: 0.44,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.9,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                applyTransforms()
            }
        } else {
            applyTransforms()
        }
    }

    func installHostedTransportBar(in hostView: UIView) {
        guard presentationContext == .nestedPagingHost else { return }
        if transportBarContainer.superview !== hostView {
            transportBarContainer.removeFromSuperview()
            hostView.addSubview(transportBarContainer)
        }
        activateTransportBarPositionConstraints(relativeTo: hostView)
        applyNestedPagingTransportProgress(nestedPagingTransportProgress)
    }

    func stopHostedPlaybackIfDisappearing() {
        guard presentationContext == .nestedPagingHost else { return }
        stopPlayback(resetPosition: false)
    }

    /// Swaps scenario content without replacing the scroll view so top bounce and edge effects stay wired.
    func reloadScenario(
        pointTitle: String,
        example: GrammarExample,
        scenarioID: String? = nil,
        grammarPointIDs: [String]? = nil
    ) {
        stopEmphasisAnimation()
        stopPlayback(resetPosition: true)

        self.pointTitle = pointTitle
        self.example = example
        if let scenarioID { self.scenarioID = scenarioID }
        if let grammarPointIDs { self.grammarPointIDs = grammarPointIDs }
        displayLines = Self.makeDisplayLines(for: example)
        spokenLineTexts = GrammarExampleDialogueLines.lines(for: example)

        activeLineIndex = nil
        alignedLines = []
        clipDuration = 0
        audioPlayer = nil
        resolvedAudioURL = nil
        seekTargetLineIndex = nil
        playbackPhase = .idle

        if let setting = example.scenario?.setting, !setting.isEmpty {
            settingLabel.text = setting
            settingLabel.isHidden = false
        } else {
            settingLabel.text = nil
            settingLabel.isHidden = true
        }

        updateMetadataLabel()
        rebuildTranscriptRows()
        resolveLessonAudio()
        updateTransportControls()

        if presentationContext == .standalone {
            updateElapsedLabel(currentTime: 0)
        }

        resetScrollPositionForNewTranscript()
        refreshScrollEdgeEffects()
    }

    deinit {
        progressDisplayLink?.invalidate()
    }

    // MARK: - Setup

    private func configureScrollContentHeader() {
        scrollHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        scrollHeaderStack.axis = .vertical
        scrollHeaderStack.alignment = .center
        scrollHeaderStack.spacing = 10
        scrollHeaderStack.isLayoutMarginsRelativeArrangement = true
        scrollHeaderStack.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        scrollHeaderStack.insetsLayoutMarginsFromSafeArea = false

        configureSceneImageView()

        let settingBase = UIFont.preferredFont(forTextStyle: .body)
        if let italicDescriptor = settingBase.fontDescriptor.withSymbolicTraits(.traitItalic) {
            settingLabel.font = UIFont(descriptor: italicDescriptor, size: 0)
        } else {
            settingLabel.font = settingBase
        }
        settingLabel.textColor = .secondaryLabel
        settingLabel.textAlignment = .center
        settingLabel.numberOfLines = 0
        settingLabel.text = example.scenario?.setting

        metadataLabel.font = .preferredFont(forTextStyle: .footnote)
        metadataLabel.textColor = .tertiaryLabel
        metadataLabel.textAlignment = .center
        metadataLabel.numberOfLines = 0
        updateMetadataLabel()

        if sceneImageView.image != nil || sceneImageURL != nil {
            scrollHeaderStack.addArrangedSubview(sceneImageContainer)
            scrollHeaderStack.setCustomSpacing(20, after: sceneImageContainer)
            // Now that container and stack share an ancestor, the width pin is safe.
            sceneImageWidthConstraint?.isActive = true
        }
        if let setting = example.scenario?.setting, !setting.isEmpty {
            scrollHeaderStack.addArrangedSubview(settingLabel)
            scrollHeaderStack.setCustomSpacing(12, after: settingLabel)
        }
        scrollHeaderStack.addArrangedSubview(metadataLabel)
    }

    /// Scene-setting image (white border + drop shadow + 20pt rounded corners),
    /// almost the screen width, with its native aspect ratio preserved. The
    /// outer container carries the shadow; the inner image view clips the corners.
    private func configureSceneImageView() {
        if let remoteURL = sceneImageURL {
            sceneImageContainer.isHidden = false
            prepareSceneImageChrome(aspectRatio: 0.75)
            let token = remoteURL.absoluteString
            sceneImageView.accessibilityIdentifier = token

            let finishLoading: (UIImage?) -> Void = { [weak self] image in
                guard let self,
                      self.sceneImageView.accessibilityIdentifier == token else { return }
                self.hideSceneImageLoadingPlaceholder()
                if let image {
                    self.applySceneImage(image)
                } else if let bundled = self.sceneImageName.flatMap({ UIImage(named: $0) }) {
                    self.applySceneImage(bundled)
                } else {
                    self.sceneImageContainer.isHidden = true
                }
            }

            if let cached = LessonThumbnailLoader.cachedImage(for: remoteURL) {
                finishLoading(cached)
            } else {
                showSceneImageLoadingPlaceholder()
                LessonThumbnailLoader.load(url: remoteURL, completion: finishLoading)
            }
            return
        }

        hideSceneImageLoadingPlaceholder()

        guard let image = sceneImageName.flatMap({ UIImage(named: $0) }) else {
            sceneImageContainer.isHidden = true
            return
        }
        applySceneImage(image)
    }

    private func showSceneImageLoadingPlaceholder() {
        sceneImageLoadingPlaceholder.message = "Loading"
        sceneImageLoadingPlaceholder.syncCornerRadius(with: sceneImageView)
        sceneImageLoadingPlaceholder.isHidden = false
        sceneImageLoadingPlaceholder.startAnimating()
    }

    private func hideSceneImageLoadingPlaceholder() {
        sceneImageLoadingPlaceholder.stopAnimating()
        sceneImageLoadingPlaceholder.isHidden = true
    }

    private func prepareSceneImageChrome(aspectRatio: CGFloat) {
        sceneImageContainer.isHidden = false
        sceneImageContainer.translatesAutoresizingMaskIntoConstraints = false
        sceneImageContainer.backgroundColor = .clear
        sceneImageContainer.layer.shadowColor = UIColor.black.cgColor
        sceneImageContainer.layer.shadowOpacity = 0.18
        sceneImageContainer.layer.shadowRadius = 12
        sceneImageContainer.layer.shadowOffset = CGSize(width: 0, height: 6)

        sceneImageView.translatesAutoresizingMaskIntoConstraints = false
        sceneImageView.contentMode = .scaleAspectFill
        sceneImageView.clipsToBounds = true
        sceneImageView.layer.cornerRadius = ImageLoadingPlaceholderMetrics.defaultCornerRadius
        sceneImageView.layer.cornerCurve = .continuous
        sceneImageView.layer.borderWidth = 3
        sceneImageView.layer.borderColor = UIColor.white.cgColor
        if sceneImageView.superview == nil {
            sceneImageContainer.addSubview(sceneImageView)
        }
        if sceneImageLoadingPlaceholder.superview == nil {
            sceneImageLoadingPlaceholder.translatesAutoresizingMaskIntoConstraints = false
            sceneImageLoadingPlaceholder.message = "Loading"
            sceneImageLoadingPlaceholder.syncCornerRadius(with: sceneImageView)
            sceneImageLoadingPlaceholder.isHidden = true
            sceneImageContainer.addSubview(sceneImageLoadingPlaceholder)
            NSLayoutConstraint.activate([
                sceneImageLoadingPlaceholder.topAnchor.constraint(equalTo: sceneImageView.topAnchor),
                sceneImageLoadingPlaceholder.leadingAnchor.constraint(equalTo: sceneImageView.leadingAnchor),
                sceneImageLoadingPlaceholder.trailingAnchor.constraint(equalTo: sceneImageView.trailingAnchor),
                sceneImageLoadingPlaceholder.bottomAnchor.constraint(equalTo: sceneImageView.bottomAnchor),
            ])
        }

        sceneImageContainer.constraints
            .filter { $0.firstAttribute == .height || $0.secondAttribute == .height }
            .forEach { $0.isActive = false }
        sceneImageView.constraints
            .filter {
                $0.firstAttribute == .top || $0.firstAttribute == .bottom
                    || $0.firstAttribute == .leading || $0.firstAttribute == .trailing
            }
            .forEach { $0.isActive = false }

        NSLayoutConstraint.activate([
            sceneImageView.topAnchor.constraint(equalTo: sceneImageContainer.topAnchor),
            sceneImageView.leadingAnchor.constraint(equalTo: sceneImageContainer.leadingAnchor),
            sceneImageView.trailingAnchor.constraint(equalTo: sceneImageContainer.trailingAnchor),
            sceneImageView.bottomAnchor.constraint(equalTo: sceneImageContainer.bottomAnchor),
            sceneImageContainer.heightAnchor.constraint(
                equalTo: sceneImageContainer.widthAnchor,
                multiplier: aspectRatio
            ),
        ])
        if sceneImageWidthConstraint == nil {
            sceneImageWidthConstraint = makeSceneImageWidthConstraint()
        }
    }

    /// Speaker-listening mode shrinks the hero image so the header and both
    /// speaker bubbles fit the viewport without scrolling; the other modes
    /// scroll, so they keep the wide image.
    private func makeSceneImageWidthConstraint() -> NSLayoutConstraint {
        sceneImageContainer.widthAnchor.constraint(
            equalTo: scrollHeaderStack.widthAnchor,
            multiplier: transcriptDisplayMode == .listeningSpeakers ? 0.72 : 0.92
        )
    }

    private func updateSceneImageWidthForCurrentMode() {
        guard let existing = sceneImageWidthConstraint else { return }
        let wasActive = existing.isActive
        existing.isActive = false
        let updated = makeSceneImageWidthConstraint()
        sceneImageWidthConstraint = updated
        updated.isActive = wasActive
    }

    private func applySceneImage(_ image: UIImage) {
        hideSceneImageLoadingPlaceholder()
        sceneImageView.image = image
        sceneImageContainer.isHidden = false
        let aspect = image.size.height / max(image.size.width, 1)
        prepareSceneImageChrome(aspectRatio: aspect)
        sceneImageView.layer.borderColor = UIColor.white.cgColor
        // Almost the full content width; aspect ratio preserved from the asset.
        // Pinned to the header stack, so it can only be activated once the
        // container has actually been added to that stack (see header build).
        if sceneImageWidthConstraint == nil {
            sceneImageWidthConstraint = makeSceneImageWidthConstraint()
        }
    }

    private func attachTopScrollEdgeInteraction() {
        topScrollEdgeInteraction.scrollView = scrollView
        navigationController?.navigationBar.addInteraction(topScrollEdgeInteraction)
    }

    private func updateMetadataLabel() {
        metadataLabel.text = Self.metadataText(
            pointTitle: pointTitle,
            lineCount: displayLines.count,
            duration: clipDuration
        )
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        scrollView.delaysContentTouches = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 48
        contentStack.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        contentStack.isLayoutMarginsRelativeArrangement = true
        // The scroll view sweeps the safe-area boundary through content near the
        // top; opting out stops per-frame margin relayout of the whole transcript.
        contentStack.insetsLayoutMarginsFromSafeArea = false
        scrollView.addSubview(contentStack)

        contentStackTopConstraint = contentStack.topAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.topAnchor,
            constant: 0
        )

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackTopConstraint,
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func configureTransportBar() {
        transportBarContainer.translatesAutoresizingMaskIntoConstraints = false
        transportBarContainer.backgroundColor = .clear
        transportBarContainer.addInteraction(bottomScrollEdgeInteraction)

        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        elapsedLabel.textColor = .label
        elapsedLabel.textAlignment = .center
        elapsedLabel.text = "00:00.00"

        Self.configureGlassTransportButton(
            playPauseButton,
            glyphView: playGlyphView,
            symbolName: "play.fill",
            glyphPointSize: Self.transportGlyphPointSize,
            accessibilityLabel: "Play / Pause"
        )
        playPauseButton.addAction(UIAction { [weak self] _ in self?.togglePlayPause() }, for: .primaryActionTriggered)

        Self.configureGlassTransportButton(
            speedButton,
            glyphView: speedGlyphView,
            symbolName: "gauge.with.dots.needle.67percent",
            glyphPointSize: Self.transportGlyphPointSize - 2,
            accessibilityLabel: "Playback speed"
        )
        speedButton.showsMenuAsPrimaryAction = true
        speedButton.menu = makeSpeedMenu()

        Self.configureGlassTransportButton(
            restartButton,
            glyphView: restartGlyphView,
            symbolName: "arrow.counterclockwise",
            glyphPointSize: Self.transportGlyphPointSize - 2,
            accessibilityLabel: "Restart"
        )
        restartButton.addAction(UIAction { [weak self] _ in self?.restartTapped() }, for: .primaryActionTriggered)

        leftTransportControlsStack.translatesAutoresizingMaskIntoConstraints = false
        leftTransportControlsStack.axis = .horizontal
        leftTransportControlsStack.alignment = .center
        leftTransportControlsStack.spacing = 8
        leftTransportControlsStack.addArrangedSubview(speedButton)
        leftTransportControlsStack.addArrangedSubview(restartButton)

        transportBarContainer.addSubview(leftTransportControlsStack)
        transportBarContainer.addSubview(elapsedLabel)
        transportBarContainer.addSubview(playPauseButton)

        elapsedLabel.isHidden = presentationContext == .nestedPagingHost

        let horizontalInset: CGFloat = 20
        let buttonSize = Self.transportButtonSize

        NSLayoutConstraint.activate([
            leftTransportControlsStack.leadingAnchor.constraint(equalTo: transportBarContainer.leadingAnchor, constant: horizontalInset),
            leftTransportControlsStack.topAnchor.constraint(equalTo: transportBarContainer.topAnchor, constant: 8),
            leftTransportControlsStack.bottomAnchor.constraint(equalTo: transportBarContainer.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            speedButton.widthAnchor.constraint(equalToConstant: buttonSize),
            speedButton.heightAnchor.constraint(equalToConstant: buttonSize),
            restartButton.widthAnchor.constraint(equalToConstant: buttonSize),
            restartButton.heightAnchor.constraint(equalToConstant: buttonSize),

            playPauseButton.trailingAnchor.constraint(equalTo: transportBarContainer.trailingAnchor, constant: -horizontalInset),
            playPauseButton.centerYAnchor.constraint(equalTo: leftTransportControlsStack.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: buttonSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: buttonSize),

            elapsedLabel.centerXAnchor.constraint(equalTo: transportBarContainer.centerXAnchor),
            elapsedLabel.centerYAnchor.constraint(equalTo: leftTransportControlsStack.centerYAnchor),
            elapsedLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftTransportControlsStack.trailingAnchor, constant: 12),
            elapsedLabel.trailingAnchor.constraint(lessThanOrEqualTo: playPauseButton.leadingAnchor, constant: -12),
        ])

        if presentationContext == .standalone {
            view.addSubview(transportBarContainer)
            activateTransportBarPositionConstraints(relativeTo: view)
        }
    }

    private func activateTransportBarPositionConstraints(relativeTo container: UIView) {
        NSLayoutConstraint.deactivate(transportBarPositionConstraints)
        transportBarPositionConstraints = [
            transportBarContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            transportBarContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            transportBarContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        NSLayoutConstraint.activate(transportBarPositionConstraints)
    }

    private func makeSpeedMenu() -> UIMenu {
        let actions = Self.playbackSpeedOptions.map { speed in
            UIAction(
                title: Self.speedMenuTitle(for: speed),
                state: abs(speed - playbackSpeed) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.setPlaybackSpeed(speed)
            }
        }
        return UIMenu(title: "Playback speed", options: .singleSelection, children: actions)
    }

    private func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioPlayer?.enableRate = true
        if audioPlayer?.isPlaying == true {
            audioPlayer?.rate = speed
        }
        speedButton.menu = makeSpeedMenu()
    }

    private static func speedMenuTitle(for speed: Float) -> String {
        if abs(speed - 1.0) < 0.01 {
            return "1.0× Normal"
        }
        return String(format: "%.1f×", speed)
    }

    private func rebuildTranscriptRows() {
        for v in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        lineRows.removeAll()
        japaneseBubbles.removeAll()
        japaneseLabels.removeAll()
        englishLabels.removeAll()
        listeningSpeakerSlots.removeAll()
        listeningLineMeters.removeAll()
        lineRevealLevels.removeAll()
        lineRevealTravels.removeAll()
        lineRevealSlots.removeAll()
        bubbleMinWidthConstraints.removeAll()
        bubbleSwipeContainers.removeAll()
        messageColumnLayouts.removeAll()
        lineEmphasis = Array(repeating: 0, count: displayLines.count)
        appliedRowSpacingEmphasis.removeAll()
        appliedBubbleMinWidthColumnWidth = -1

        contentStack.addArrangedSubview(scrollHeaderStack)
        contentStack.setCustomSpacing(64, after: scrollHeaderStack)

        if transcriptDisplayMode == .listeningSpeakers {
            buildListeningSpeakerRows()
            applyListeningSpeakerFocus(animated: false)
            return
        }

        if transcriptDisplayMode == .reveal {
            lineRevealLevels = Array(repeating: .audioOnly, count: displayLines.count)
            lineRevealTravels = Array(repeating: .revealing, count: displayLines.count)
        }

        for (idx, line) in displayLines.enumerated() {
            let row = makeLineRow(line: line, index: idx)
            contentStack.addArrangedSubview(row)
            lineRows.append(row)

            if idx < displayLines.count - 1 {
                let nextLine = displayLines[idx + 1]
                let spacing: CGFloat = nextLine.speaker == line.speaker ? 20 : 48
                contentStack.setCustomSpacing(spacing, after: row)
            }
        }
        if transcriptDisplayMode != .listeningLines, transcriptDisplayMode != .reveal {
            // Line-meter bubbles carry their own tinted underglow from the row
            // builder; the generic pass would stomp it with the default config.
            applyBubbleBackgroundStyleToAllBubbles()
        }
        syncLineEmphasisToActiveIndex(animated: false)
        applyRowStylesFromEmphasis()
    }

    // MARK: - Listening mode (hidden dialogue text)

    private static let listeningInactiveBubbleEmphasis: CGFloat = 0.4

    /// One static bubble per speaker: name label plus a speaker-tinted live
    /// meter. Leading speaker sits left with the name above the bubble;
    /// trailing sits right with the name below, mirroring the mock.
    private func buildListeningSpeakerRows() {
        var orderedSpeakers: [(speaker: String, side: DialogueSpeakerSide)] = []
        for line in displayLines where !orderedSpeakers.contains(where: { $0.speaker == line.speaker }) {
            orderedSpeakers.append((line.speaker, line.speakerSide))
        }

        for (slotIndex, entry) in orderedSpeakers.enumerated() {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let column = UIStackView()
            column.translatesAutoresizingMaskIntoConstraints = false
            column.axis = .vertical
            column.spacing = 10
            column.alignment = entry.side == .leading ? .leading : .trailing

            let nameLabel = UILabel()
            nameLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
            nameLabel.textColor = .secondaryLabel
            nameLabel.text = Self.speakerPrefix(for: entry.speaker)
            let nameWrapper = Self.insetMetadataWrapper(around: nameLabel, side: entry.side)

            let placeholderLabel = FuriganaTranscriptLabel()
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.alpha = 0
            let bubble = DialogueJapaneseBubbleView(label: placeholderLabel)
            bubble.setBackgroundStyle(.glass)
            var glowConfig = DialogueBubbleUnderglowConfiguration.default
            glowConfig.color = entry.side == .leading ? .blue : .yellow
            // The default glow is tuned for wide text bubbles; on this small
            // pill its blur/shadow bleeds past the silhouette. Tuck it inside.
            glowConfig.horizontalInset = 12
            glowConfig.blurRadius = 8
            glowConfig.offsetX = 0
            bubble.setUnderglowConfiguration(glowConfig)

            let meter = makeListeningMeterView(for: entry.side)
            bubble.addSubview(meter)

            if entry.side == .leading {
                column.addArrangedSubview(nameWrapper)
                column.addArrangedSubview(bubble)
            } else {
                column.addArrangedSubview(bubble)
                column.addArrangedSubview(nameWrapper)
            }

            container.addSubview(column)

            var constraints: [NSLayoutConstraint] = [
                // The empty-labeled bubble sizes to the meter plus padding.
                meter.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 36),
                meter.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -36),
                meter.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 16),
                meter.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -16),

                column.topAnchor.constraint(equalTo: container.topAnchor),
                column.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
            switch entry.side {
            case .leading:
                constraints += [
                    column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    column.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                ]
            case .trailing:
                constraints += [
                    column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    column.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
                ]
            }
            NSLayoutConstraint.activate(constraints)

            contentStack.addArrangedSubview(container)
            if slotIndex < orderedSpeakers.count - 1 {
                contentStack.setCustomSpacing(48, after: container)
            }
            listeningSpeakerSlots.append(
                ListeningSpeakerSlot(speaker: entry.speaker, side: entry.side, bubble: bubble, meter: meter)
            )
        }
    }

    /// Bar geometry and shaping mirror the tuned Speaking Meters experiment
    /// (8pt bars / 6pt gaps, curve 1.05, wobble 0.25, diamond 0.25); min height
    /// matches bar width so resting bars read as dots. Gain and smoothing are
    /// adapted for the AVAudioPlayer metering driver, which runs quieter and
    /// smoother than the experiment's FFT tap — smoothing sits high so attack
    /// lands the syllable it belongs to and release stays quick.
    private func makeListeningMeterView(for side: DialogueSpeakerSide) -> AudioLevelBarsView {
        let meter = AudioLevelBarsView()
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.barWidth = 8
        meter.barSpacing = 6
        meter.meterHeight = 52
        meter.minBarHeight = 8
        meter.heightFill = 0.95
        meter.levelGain = 1.6
        meter.displayCurve = 1.05
        meter.smoothing = 0.66
        // Keep decorative motion minimal — visible movement should come from
        // the audio itself, or sustained speech reads as random floating.
        meter.wobbleAmount = 0.08
        meter.diamondFalloff = 0.25
        meter.springiness = 0.5
        meter.historyStride = 2
        meter.barColor = side == .leading ? .systemBlue : .systemYellow
        return meter
    }

    private var activeListeningSpeaker: String? {
        guard let index = activeLineIndex, displayLines.indices.contains(index) else { return nil }
        return displayLines[index].speaker
    }

    /// Glass + underglow + scale pull focus to whichever speaker is talking.
    private func applyListeningSpeakerFocus(animated: Bool) {
        guard !listeningSpeakerSlots.isEmpty else { return }
        let activeSpeaker = activeListeningSpeaker
        let apply = {
            for slot in self.listeningSpeakerSlots {
                let isActive = slot.speaker == activeSpeaker
                slot.bubble.setEmphasis(isActive ? 1 : Self.listeningInactiveBubbleEmphasis)
                self.applyBubbleEmphasisTransform(
                    to: slot.bubble,
                    emphasis: isActive ? 1 : 0,
                    side: slot.side
                )
            }
        }
        guard animated else {
            apply()
            return
        }
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: apply
        )
    }

    private func updateListeningMetersFromPlayback(_ player: AVAudioPlayer) {
        guard !listeningSpeakerSlots.isEmpty || !listeningLineMeters.isEmpty else { return }
        player.updateMeters()

        // Take the hottest channel: dialogue clips can pan speakers apart,
        // which starves a single-channel read for one side of the conversation.
        var averageDB: Float = -160
        var peakDB: Float = -160
        for channel in 0..<max(1, player.numberOfChannels) {
            averageDB = max(averageDB, player.averagePower(forChannel: channel))
            peakDB = max(peakDB, player.peakPower(forChannel: channel))
        }

        // Telemetry showed AVAudioPlayer's peakPower is a slow-decay peak-hold
        // (frozen near -3dB for seconds), so it only added a constant offset —
        // averagePower alone carries the word rhythm. Normalize in the decibel
        // domain, then expand the speech band (≈-28…-5dB → 0…1) to full swing;
        // without the expansion a 23dB word swing moved the bars ~4pt.
        let avgNorm = Self.normalizedMeterLevel(averageDB)
        let expanded = max(0, min(1, (avgNorm - 0.18) / 0.62))

        // Rising-edge emphasis stands in for the transients the (unusable)
        // peak meter was meant to provide: compare against a slow baseline so
        // syllable onsets overshoot briefly.
        listeningMeterBaseline += (expanded - listeningMeterBaseline) * 0.06
        let attack = max(0, expanded - listeningMeterBaseline)
        let level = min(1, expanded + attack * 0.5)

        // Before the first aligned line there is no active index yet; attribute
        // clip-intro audio to the opening speaker so the bars never sit dead
        // while sound is audible.
        let activeSpeaker = activeListeningSpeaker ?? displayLines.first?.speaker
        for slot in listeningSpeakerSlots {
            if slot.speaker == activeSpeaker {
                slot.meter.setLevel(level)
            } else if !slot.meter.isIdle {
                slot.meter.releaseToRest()
            }
        }

        // Per-line mode: only the active line's meter animates. In reveal mode,
        // skip lines that have already advanced past the audio-only level.
        let activeLine = activeLineIndex ?? (listeningLineMeters.isEmpty ? nil : 0)
        for (index, meter) in listeningLineMeters.enumerated() {
            let isAudioOnlyReveal = transcriptDisplayMode != .reveal
                || (lineRevealLevels.indices.contains(index) && lineRevealLevels[index] == .audioOnly)
            if index == activeLine, isAudioOnlyReveal {
                meter.setLevel(level)
            } else if !meter.isIdle {
                meter.releaseToRest()
            }
        }

        #if DEBUG
        logListeningMeterTelemetry(
            player: player,
            averageDB: averageDB,
            peakDB: peakDB,
            level: level,
            activeSpeaker: activeSpeaker
        )
        #endif
    }

    #if DEBUG
    /// Set false to silence the ~10Hz meter telemetry in listening mode.
    private static let logsListeningMeterTelemetry = true
    private static var meterTelemetryTickCounter = 0

    private func logListeningMeterTelemetry(
        player: AVAudioPlayer,
        averageDB: Float,
        peakDB: Float,
        level: Float,
        activeSpeaker: String?
    ) {
        guard Self.logsListeningMeterTelemetry else { return }
        Self.meterTelemetryTickCounter += 1
        guard Self.meterTelemetryTickCounter % 6 == 0 else { return }
        guard let slot = listeningSpeakerSlots.first(where: { $0.speaker == activeSpeaker }) else { return }
        print(String(
            format: "[meter] t=%6.2f %@ avg=%6.1fdB peak=%6.1fdB lvl=%.2f %@",
            player.currentTime,
            (activeSpeaker ?? "?").padding(toLength: 10, withPad: " ", startingAt: 0),
            averageDB,
            peakDB,
            level,
            slot.meter.debugBarSnapshot()
        ))
    }
    #endif

    /// Maps meter decibels onto 0…1. The floor sits just under conversational
    /// consonant level so intra-word dips actually pull the bars down —
    /// a deeper floor keeps sustained speech pinned in a narrow mid band.
    private static func normalizedMeterLevel(_ decibels: Float) -> Float {
        let floorDB: Float = -38
        return max(0, min(1, (decibels - floorDB) / -floorDB))
    }

    private func releaseListeningMetersToRest() {
        listeningSpeakerSlots.forEach { $0.meter.releaseToRest() }
        listeningLineMeters.forEach { $0.releaseToRest() }
        listeningMeterBaseline = 0
    }

    /// Single scroll at play start so both speaker bubbles sit in frame (the
    /// scene image may push the second bubble below the fold).
    private func scrollListeningBubblesIntoView() {
        guard transcriptDisplayMode == .listeningSpeakers, !listeningSpeakerSlots.isEmpty,
              let lastRow = contentStack.arrangedSubviews.last else { return }
        scrollView.layoutIfNeeded()
        let rowFrame = rowBoundsInScrollableContent(lastRow)
        let inset = scrollView.adjustedContentInset
        let targetY = rowFrame.maxY - scrollView.bounds.height + inset.bottom + Self.followAlongBottomBuffer
        guard let clamped = scrollView.clampedContentOffsetY(targetY, allowNoScroll: true),
              clamped > scrollView.contentOffset.y + 1 else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: clamped), animated: true)
    }

    private func applyBubbleBackgroundStyleToAllBubbles() {
        for bubble in japaneseBubbles {
            bubble.setBackgroundStyle(.glass)
            bubble.setUnderglowConfiguration(.default)
        }
    }

    private func makeLineRow(line: DialogueLineDisplay, index: Int) -> UIView {
        let lineContainer = UIView()
        lineContainer.translatesAutoresizingMaskIntoConstraints = false
        lineContainer.tag = index
        lineContainer.isUserInteractionEnabled = true
        let lineTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
        lineContainer.addGestureRecognizer(lineTapGesture)

        let messageColumn = UIStackView()
        messageColumn.translatesAutoresizingMaskIntoConstraints = false
        messageColumn.axis = .vertical
        messageColumn.spacing = 6
        messageColumn.alignment = line.speakerSide == .leading ? .leading : .trailing

        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = Self.speakerPrefix(for: line.speaker)
        let speakerWrapper = Self.insetMetadataWrapper(
            around: speakerLabel,
            side: line.speakerSide
        )
        speakerWrapper.isHidden = !line.showsSpeakerLabel

        let japaneseFont = Self.dialogueJapaneseBaseFont

        var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: japaneseFont)
        displayInsets.top += 2

        let isListeningLineMeterRow = transcriptDisplayMode == .listeningLines
        let isRevealMode = transcriptDisplayMode == .reveal
        /// Meter chrome that owns bubble sizing (listening-lines, or reveal at audio-only).
        let installsLineMeter = isListeningLineMeterRow || isRevealMode
        /// Nested paging: swipe right expands any non-listening-lines bubble.
        /// Reveal mode also wraps meter bubbles so expand + left-swipe peel work.
        let allowsBubbleSwipe = presentationContext == .nestedPagingHost
            && (isRevealMode || !isListeningLineMeterRow)

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        if installsLineMeter {
            // The bubble sizes to the meter instead; keep the label empty and
            // its hugging low so it can't out-vote the meter's width.
            // Reveal mode fills the label when the line advances to Japanese.
            japaneseLabel.alpha = 0
        } else {
            japaneseLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            JapaneseFuriganaBuilder.applyScrubDisplay(
                to: japaneseLabel,
                attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                    for: line.japanese,
                    font: japaneseFont,
                    textColor: Self.inactiveJapaneseColor
                ),
                contentInsets: displayInsets
            )
        }

        let japaneseBubble = DialogueJapaneseBubbleView(label: japaneseLabel)
        japaneseBubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        japaneseBubble.setContentCompressionResistancePriority(.required, for: .horizontal)

        var revealMeterBubbleSizingConstraints: [NSLayoutConstraint] = []
        var revealMeterParkConstraints: [NSLayoutConstraint] = []
        var revealMeter: AudioLevelBarsView?
        if installsLineMeter {
            // Meter owns bubble size; detach the empty label so its edge pins
            // can't fight the meter (critical when cycling back from Japanese).
            japaneseBubble.setLabelContributesToLayout(false)
            japaneseBubble.setBackgroundStyle(.glass)
            var glowConfig = DialogueBubbleUnderglowConfiguration.default
            glowConfig.color = line.speakerSide == .leading ? .blue : .yellow
            glowConfig.horizontalInset = 12
            glowConfig.blurRadius = 8
            glowConfig.offsetX = 0
            japaneseBubble.setUnderglowConfiguration(glowConfig)

            let meter = makeListeningMeterView(for: line.speakerSide)
            meter.meterHeight = 36
            japaneseBubble.addSubview(meter)

            let meterIntrinsic = meter.intrinsicContentSize
            let parkConstraints = [
                meter.centerXAnchor.constraint(equalTo: japaneseBubble.centerXAnchor),
                meter.centerYAnchor.constraint(equalTo: japaneseBubble.centerYAnchor),
                meter.widthAnchor.constraint(equalToConstant: meterIntrinsic.width),
                meter.heightAnchor.constraint(equalToConstant: meter.meterHeight),
            ]
            let bubbleSizingConstraints = [
                japaneseBubble.widthAnchor.constraint(
                    equalTo: meter.widthAnchor,
                    constant: 56
                ),
                japaneseBubble.heightAnchor.constraint(
                    equalTo: meter.heightAnchor,
                    constant: 24
                ),
            ]

            if isRevealMode {
                // Park (center + fixed size) is always on so the meter has a
                // valid layout. Bubble-sizing constraints are only for audio-only.
                NSLayoutConstraint.activate(parkConstraints + bubbleSizingConstraints)
                revealMeter = meter
                revealMeterBubbleSizingConstraints = bubbleSizingConstraints
                revealMeterParkConstraints = parkConstraints
            } else {
                // Listening-lines: meter edge-pins the bubble (label stays detached).
                NSLayoutConstraint.activate([
                    meter.leadingAnchor.constraint(equalTo: japaneseBubble.leadingAnchor, constant: 28),
                    meter.trailingAnchor.constraint(equalTo: japaneseBubble.trailingAnchor, constant: -28),
                    meter.topAnchor.constraint(equalTo: japaneseBubble.topAnchor, constant: 12),
                    meter.bottomAnchor.constraint(equalTo: japaneseBubble.bottomAnchor, constant: -12),
                ])
            }
            listeningLineMeters.append(meter)
        }

        messageColumn.addArrangedSubview(speakerWrapper)

        let bubbleLayoutTarget: UIView
        if allowsBubbleSwipe {
            let swipeContainer = DialogueBubbleSwipeRevealContainer(bubbleView: japaneseBubble)
            swipeContainer.hostScrollView = scrollView
            swipeContainer.onCommit = { [weak self] in
                self?.presentSentenceFocus(forLineAt: index)
            }
            if isRevealMode {
                swipeContainer.allowsProgressiveReveal = true
                swipeContainer.onProgressiveRevealCommit = { [weak self] in
                    self?.advanceRevealLevel(at: index, animated: true)
                }
            }
            swipeContainer.configureContentPopGestureDeferral(from: self)
            bubbleSwipeContainers.append(swipeContainer)
            lineTapGesture.require(toFail: swipeContainer.panGestureRecognizer)
            bubbleLayoutTarget = swipeContainer
            messageColumn.addArrangedSubview(swipeContainer)
        } else {
            bubbleLayoutTarget = japaneseBubble
            messageColumn.addArrangedSubview(japaneseBubble)
        }

        var revealTextMinWidthConstraint: NSLayoutConstraint?
        if !installsLineMeter {
            let minBubbleWidth = Self.minimumBubbleWidth(
                for: line,
                columnMaxWidth: availableMessageColumnWidth()
            )
            let minBubbleWidthConstraint = bubbleLayoutTarget.widthAnchor.constraint(
                greaterThanOrEqualToConstant: minBubbleWidth
            )
            minBubbleWidthConstraint.priority = .required
            minBubbleWidthConstraint.isActive = true
            bubbleMinWidthConstraints.append(minBubbleWidthConstraint)
        } else if isRevealMode {
            let minBubbleWidth = Self.minimumBubbleWidth(
                for: line,
                columnMaxWidth: availableMessageColumnWidth()
            )
            let minBubbleWidthConstraint = bubbleLayoutTarget.widthAnchor.constraint(
                greaterThanOrEqualToConstant: minBubbleWidth
            )
            minBubbleWidthConstraint.priority = .required
            minBubbleWidthConstraint.isActive = false
            revealTextMinWidthConstraint = minBubbleWidthConstraint
            bubbleMinWidthConstraints.append(minBubbleWidthConstraint)
        }

        japaneseLabels.append(japaneseLabel)
        japaneseBubbles.append(japaneseBubble)

        var hasEnglishTranslation = false
        var revealEnglishWrapper: UIView?
        let englishText = line.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldBuildEnglish = (transcriptDisplayMode == .full || isRevealMode) && !englishText.isEmpty
        if shouldBuildEnglish {
            let englishLabel = UILabel()
            englishLabel.font = Self.englishFont
            englishLabel.textColor = Self.englishColor
            englishLabel.numberOfLines = 0
            englishLabel.textAlignment = line.speakerSide == .trailing ? .right : .left
            englishLabel.text = englishText
            let englishWrapper = Self.insetMetadataWrapper(
                around: englishLabel,
                side: line.speakerSide
            )
            if isRevealMode {
                englishWrapper.isHidden = true
                englishWrapper.alpha = 0
                revealEnglishWrapper = englishWrapper
            } else {
                hasEnglishTranslation = true
            }
            messageColumn.addArrangedSubview(englishWrapper)
            englishLabels.append(englishLabel)
        } else {
            englishLabels.append(UILabel())
        }

        if isRevealMode, let meter = revealMeter {
            var slot = LineRevealSlot(
                meter: meter,
                meterBubbleSizingConstraints: revealMeterBubbleSizingConstraints,
                meterParkConstraints: revealMeterParkConstraints,
                englishWrapper: revealEnglishWrapper
            )
            slot.textMinWidthConstraint = revealTextMinWidthConstraint
            lineRevealSlots.append(slot)
        }

        messageColumnLayouts.append(
            LineMessageColumnLayout(
                column: messageColumn,
                viewBeforeBubble: speakerWrapper,
                bubbleView: bubbleLayoutTarget,
                hasEnglish: hasEnglishTranslation
            )
        )

        lineContainer.addSubview(messageColumn)

        let maxWidth = messageColumn.widthAnchor.constraint(
            lessThanOrEqualTo: lineContainer.widthAnchor,
            multiplier: Self.messageColumnMaxWidthRatio
        )
        maxWidth.priority = .required

        var layoutConstraints: [NSLayoutConstraint] = [
            messageColumn.topAnchor.constraint(equalTo: lineContainer.topAnchor),
            messageColumn.bottomAnchor.constraint(equalTo: lineContainer.bottomAnchor),
            maxWidth,
        ]

        switch line.speakerSide {
        case .leading:
            layoutConstraints += [
                messageColumn.leadingAnchor.constraint(equalTo: lineContainer.leadingAnchor),
                messageColumn.trailingAnchor.constraint(lessThanOrEqualTo: lineContainer.trailingAnchor),
            ]
        case .trailing:
            layoutConstraints += [
                messageColumn.trailingAnchor.constraint(equalTo: lineContainer.trailingAnchor),
                messageColumn.leadingAnchor.constraint(greaterThanOrEqualTo: lineContainer.leadingAnchor),
            ]
        }

        NSLayoutConstraint.activate(layoutConstraints)
        return lineContainer
    }

    // MARK: - Audio

    private func resolveLessonAudio() {
        GrammarAudioCatalog.ensureLocalURL(
            publishedAudioUrl: example.publishedAudioUrl,
            audioKey: example.audioKey,
            cacheMetadata: example.remoteAudioCacheMetadata
        ) { [weak self] url in
            guard let self else { return }
            self.resolvedAudioURL = url
            self.prepareAudioAlignment()
            self.updateTransportControls()
            if self.presentationContext == .standalone {
                self.updateElapsedLabel(currentTime: 0)
            }
        }
    }

    private func prepareAudioAlignment() {
        guard let url = resolvedAudioURL else {
            return
        }

        clipDuration = playerDuration(for: url)
        updateMetadataLabel()

        let pcm = try? TTSAudioFileLoader.loadMonoFloatSamples(from: url)
        alignedLines = TTSAudioAlignment.segmentTimeRanges(
            lineTexts: spokenLineTexts,
            duration: clipDuration,
            samples: pcm?.samples,
            sampleRate: pcm?.sampleRate ?? 24_000,
            audioURL: url
        )

        if let alignmentDebugLog {
            alignmentDebugLog("clip duration \(String(format: "%.3f", clipDuration))s · PCM \(pcm?.samples.count ?? 0) samples @ \(Int(pcm?.sampleRate ?? 24_000)) Hz")
            if let embedded = DialogueAlignmentMetadata.readLineSwitchSeconds(from: url) {
                alignmentDebugLog("embedded M4A line switches: \(embedded.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
            }
            if alignedLines.isEmpty {
                alignmentDebugLog("WARNING: no aligned lines produced")
            } else {
                for (index, line) in alignedLines.enumerated() {
                    let lo = String(format: "%.3f", line.timeRange.lowerBound)
                    let hi = String(format: "%.3f", line.timeRange.upperBound)
                    alignmentDebugLog("aligned[\(index)] switch≥\(lo)s · range \(lo)–\(hi)s · \"\(line.text)\"")
                }
            }
        }
    }

    private func playerDuration(for url: URL) -> TimeInterval {
        if let audioPlayer, audioPlayer.url == url, audioPlayer.duration > 0 {
            return audioPlayer.duration
        }
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return 0 }
        player.isMeteringEnabled = true
        audioPlayer = player
        player.prepareToPlay()
        return player.duration
    }

    @discardableResult
    private func makePlayer() -> AVAudioPlayer? {
        guard let url = resolvedAudioURL else {
            return nil
        }
        if let audioPlayer, audioPlayer.url == url {
            return audioPlayer
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.enableRate = true
        player.isMeteringEnabled = true
        player.prepareToPlay()
        audioPlayer = player
        return player
    }

    private func applyPlaybackSpeedToPlayer() {
        audioPlayer?.enableRate = true
        audioPlayer?.rate = playbackSpeed
    }

    private func startPlayback(fromBeginning: Bool) {
        guard let player = makePlayer() else { return }

        seekTargetLineIndex = nil

        if fromBeginning {
            player.currentTime = 0
        }
        if transcriptDisplayMode == .listeningSpeakers {
            scrollListeningBubblesIntoView()
        } else if fromBeginning {
            scrollToTranscriptTop(animated: true)
        }

        playbackPhase = .playing
        updateTransportControls()
        syncActiveLineFromPlaybackTime(player.currentTime, animated: true)
        startPlayerAfterSessionActivation(player)
    }

    /// Activates the audio session off the main thread, then starts `player` once
    /// it completes. The synchronous `setActive` blocks long enough to drop frames
    /// of the line-emphasis animation, so UI state flips to `.playing` immediately
    /// and the player starts when the session is ready. The completion no-ops if
    /// playback was paused/stopped or superseded by a newer request in the gap.
    private func startPlayerAfterSessionActivation(_ player: AVAudioPlayer) {
        playbackActivationGeneration += 1
        let generation = playbackActivationGeneration
        // Stamped at request time as well as at play() so handleProgressTick's
        // finished-playback fallback (phase == .playing but player stopped for
        // >0.12s) doesn't fire while session activation is still in flight.
        playbackResumeStartedAt = CACurrentMediaTime()

        PlaybackAudioSession.activateForPlayback { [weak self] success in
            guard let self, self.playbackActivationGeneration == generation else { return }
            guard self.playbackPhase == .playing else { return }
            guard success else {
                self.playbackPhase = .idle
                self.updateTransportControls()
                return
            }
            self.playbackResumeStartedAt = CACurrentMediaTime()
            player.play()
            self.applyPlaybackSpeedToPlayer()
            self.startProgressDisplayLink()
        }
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        playbackPhase = .paused
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        updateTransportControls()
    }

    private func resumePlayback() {
        guard let player = audioPlayer else { return }
        seekTargetLineIndex = nil
        scrollListeningBubblesIntoView()
        playbackResumeStartedAt = CACurrentMediaTime()
        player.play()
        applyPlaybackSpeedToPlayer()
        playbackPhase = .playing
        startProgressDisplayLink()
        updateTransportControls()
    }

    private func stopPlayback(resetPosition: Bool) {
        // With resetPosition false the phase is left as-is, so the phase guard in
        // startPlayerAfterSessionActivation wouldn't catch a pending activation;
        // invalidate it by generation so stopped audio can't restart itself.
        playbackActivationGeneration += 1
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        seekTargetLineIndex = nil
        audioPlayer?.stop()
        if resetPosition {
            audioPlayer?.currentTime = 0
            playbackPhase = .idle
            setActiveLine(nil, animated: false)
            updateElapsedLabel(currentTime: 0)
        }
        updateTransportControls()
    }

    private func handlePlaybackFinished() {
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        playbackPhase = .finished
        setActiveLine(nil, animated: true)
        updateElapsedLabel(currentTime: clipDuration)
        updateTransportControls()
        recordScenarioCompletionIfNeeded()
    }

    private func recordScenarioCompletionIfNeeded() {
        guard recordsCompletionOnPlaybackFinish, let scenarioID else { return }
        DialogueProgressStore.shared.markCompleted(scenarioID: scenarioID)
        GrammarMasteryStore.shared.recordEncounter(
            grammarIDs: grammarPointIDs,
            scenarioID: scenarioID
        )
    }

    private func startProgressDisplayLink() {
        stopProgressDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(handleProgressTick))
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
    }

    private func stopProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    @objc private func handleProgressTick() {
        guard let player = audioPlayer, player.isPlaying else {
            if playbackPhase == .playing,
               CACurrentMediaTime() - playbackResumeStartedAt > 0.12 {
                handlePlaybackFinished()
            }
            return
        }

        let time = player.currentTime
        updateElapsedLabel(currentTime: time)
        syncActiveLineFromPlaybackTime(time, animated: true)
        updateListeningMetersFromPlayback(player)
    }

    private func syncActiveLineFromPlaybackTime(_ time: TimeInterval, animated: Bool) {
        if let targetIndex = seekTargetLineIndex,
           alignedLines.indices.contains(targetIndex) {
            let range = alignedLines[targetIndex].timeRange
            if time + 0.05 >= range.lowerBound, time < range.upperBound + 0.05 {
                seekTargetLineIndex = nil
            } else {
                setActiveLine(targetIndex, animated: false)
                return
            }
        }

        setActiveLine(lineIndex(for: time), animated: animated)
    }

    private func lineIndex(for time: TimeInterval) -> Int? {
        guard !alignedLines.isEmpty else { return nil }
        var active: Int?
        for (index, line) in alignedLines.enumerated() where time >= line.timeRange.lowerBound {
            active = index
        }
        return active
    }

    // MARK: - Active line

    private func setActiveLine(_ newIndex: Int?, animated: Bool) {
        guard newIndex != activeLineIndex else { return }

        if let alignmentDebugLog {
            let time = audioPlayer?.currentTime ?? 0
            let from = activeLineIndex.map(String.init) ?? "nil"
            let to = newIndex.map(String.init) ?? "nil"
            var detail = "line switch at t=\(String(format: "%.3f", time))s: \(from) → \(to)"
            if let newIndex, alignedLines.indices.contains(newIndex) {
                let range = alignedLines[newIndex].timeRange
                detail += " (bounds ≥\(String(format: "%.3f", range.lowerBound)) <\(String(format: "%.3f", range.upperBound)))"
                detail += " \"\(alignedLines[newIndex].text)\""
            } else if newIndex != nil {
                detail += " WARNING: index out of alignedLines range (count=\(alignedLines.count))"
            }
            alignmentDebugLog(detail)
        }

        if newIndex != nil {
            lineChangeHaptic.impactOccurred()
        }

        activeLineIndex = newIndex

        syncLineEmphasisToActiveIndex(animated: animated)
        applyListeningSpeakerFocus(animated: animated)

        if let index = newIndex, !scrollView.isTracking, !scrollView.isDecelerating {
            if animated {
                // The actual scrolling happens inside the emphasis display link so
                // the offset tracks the row spacing as it animates underneath.
                if let direction = followAlongDirection(revealingLineAt: index) {
                    followAlongScrollDirection = direction
                    followAlongScrollStartY = scrollView.contentOffset.y
                }
            } else {
                scrollView.layoutIfNeeded()
                if let direction = followAlongDirection(revealingLineAt: index),
                   let endY = followAlongEndOffsetY(revealingLineAt: index, direction: direction) {
                    scrollView.setClampedContentOffsetY(endY, allowsScrollCallback: false)
                }
            }
        }
    }

    private func syncLineEmphasisToActiveIndex(animated: Bool) {
        if lineEmphasis.count != japaneseLabels.count {
            lineEmphasis = Array(repeating: 0, count: japaneseLabels.count)
        }

        let target = japaneseLabels.indices.map { idx in
            activeLineIndex == idx ? CGFloat(1) : CGFloat(0)
        }

        stopEmphasisAnimation()

        guard animated else {
            lineEmphasis = target
            applyRowStylesFromEmphasis()
            return
        }

        emphasisAnimationStart = lineEmphasis
        emphasisAnimationTarget = target
        emphasisAnimationStartTime = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(tickEmphasisAnimation))
        link.add(to: .main, forMode: .common)
        emphasisAnimationLink = link
    }

    @objc private func tickEmphasisAnimation() {
        let elapsed = CACurrentMediaTime() - emphasisAnimationStartTime
        let progress = min(1, elapsed / Self.emphasisAnimationDuration)
        let eased = Self.emphasisEase(progress)

        lineEmphasis = zip(emphasisAnimationStart, emphasisAnimationTarget).map { start, end in
            start + (end - start) * eased
        }
        applyRowStylesFromEmphasis()
        stepFollowAlongScroll(eased: eased)

        guard progress >= 1 else { return }
        lineEmphasis = emphasisAnimationTarget
        applyRowStylesFromEmphasis()
        stepFollowAlongScroll(eased: 1)
        stopEmphasisAnimation()
    }

    /// Moves the scroll offset toward the follow-along target with the shared emphasis
    /// ease. The end offset is recomputed every frame because the animating row spacing
    /// shifts the layout; as `eased` reaches 1 the offset converges on the final layout.
    private func stepFollowAlongScroll(eased: CGFloat) {
        guard let direction = followAlongScrollDirection, let index = activeLineIndex else { return }
        if scrollView.isTracking || scrollView.isDecelerating {
            followAlongScrollDirection = nil
            return
        }
        scrollView.layoutIfNeeded()
        guard let endY = followAlongEndOffsetY(revealingLineAt: index, direction: direction) else {
            return
        }
        let y = followAlongScrollStartY + (endY - followAlongScrollStartY) * eased
        scrollView.setClampedContentOffsetY(y, allowsScrollCallback: false)
    }

    private func stopEmphasisAnimation() {
        emphasisAnimationLink?.invalidate()
        emphasisAnimationLink = nil
        followAlongScrollDirection = nil
    }

    private func resetScrollPositionForNewTranscript() {
        scrollView.layoutIfNeeded()
        let topY = -scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: 0, y: topY), animated: false)
    }

    private func refreshScrollEdgeEffects() {
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false
        bottomScrollEdgeInteraction.scrollView = scrollView
        if presentationContext == .standalone {
            topScrollEdgeInteraction.scrollView = scrollView
        }
    }

    private func scrollToTranscriptTop(animated: Bool) {
        let inset = scrollView.adjustedContentInset
        guard let targetY = scrollView.clampedContentOffsetY(-inset.top, allowNoScroll: true) else {
            return
        }
        guard abs(targetY - scrollView.contentOffset.y) >= 1 else { return }

        if animated {
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
        } else {
            scrollView.setClampedContentOffsetY(targetY, allowsScrollCallback: false)
        }
    }

    /// Row bounds in scroll-content coordinates — same axis as `contentOffset`.
    private func rowBoundsInScrollableContent(_ row: UIView) -> CGRect {
        contentStack.convert(row.bounds, from: row)
    }

    /// Which way the transcript must scroll so the line at `index` sits inside the
    /// top/bottom follow-along margins, or `nil` when it is already comfortably visible.
    private func followAlongDirection(revealingLineAt index: Int) -> FollowAlongScrollDirection? {
        guard lineRows.indices.contains(index) else { return nil }
        let row = lineRows[index]
        guard row.bounds.height > 0 else { return nil }

        let rowFrame = rowBoundsInScrollableContent(row)
        let inset = scrollView.adjustedContentInset
        let currentY = scrollView.contentOffset.y
        let visibleBottom = currentY + scrollView.bounds.height - inset.bottom - Self.followAlongBottomBuffer
        let visibleTop = currentY + Self.followAlongTopBuffer

        if rowFrame.maxY > visibleBottom { return .down }
        if rowFrame.minY < visibleTop { return .up }
        return nil
    }

    /// Final follow-along offset for the line at `index`, computed from the current
    /// layout. Returns `nil` when the content does not scroll.
    private func followAlongEndOffsetY(
        revealingLineAt index: Int,
        direction: FollowAlongScrollDirection
    ) -> CGFloat? {
        guard lineRows.indices.contains(index) else { return nil }
        let row = lineRows[index]
        guard row.bounds.height > 0 else { return nil }

        let rowFrame = rowBoundsInScrollableContent(row)
        let inset = scrollView.adjustedContentInset
        let targetY: CGFloat
        switch direction {
        case .down:
            targetY = rowFrame.maxY - scrollView.bounds.height + inset.bottom + Self.followAlongBottomBuffer
        case .up:
            targetY = rowFrame.minY - Self.followAlongTopBuffer
        }
        return scrollView.clampedContentOffsetY(targetY, allowNoScroll: true)
    }

    /// Emphasis never touches the rendered text: labels are rendered once at the
    /// base font when rows are built, and focus is conveyed by the bubble transform
    /// scale, bubble visuals, and row spacing — so focused lines never re-wrap.
    private func applyRowStylesFromEmphasis() {
        for (i, bubble) in japaneseBubbles.enumerated() {
            let emphasis = lineEmphasis.indices.contains(i) ? lineEmphasis[i] : 0
            // Meter bubbles have no text, so a fully de-emphasized glass
            // background (alpha 0) would leave nothing visible; keep the same
            // inactive floor the speaker-listening bubbles use.
            let usesMeterEmphasisFloor = transcriptDisplayMode == .listeningLines
                || (transcriptDisplayMode == .reveal
                    && lineRevealLevels.indices.contains(i)
                    && lineRevealLevels[i] == .audioOnly)
            let visualEmphasis = usesMeterEmphasisFloor
                ? Self.listeningInactiveBubbleEmphasis
                    + (1 - Self.listeningInactiveBubbleEmphasis) * emphasis
                : emphasis
            bubble.setEmphasis(visualEmphasis)
            applyBubbleEmphasisTransform(
                to: bubble,
                emphasis: emphasis,
                side: displayLines[i].speakerSide
            )
        }
        applyMessageColumnSpacingFromEmphasis()
    }

    private func applyMessageColumnSpacingFromEmphasis() {
        if appliedRowSpacingEmphasis.count != messageColumnLayouts.count {
            appliedRowSpacingEmphasis = Array(repeating: -1, count: messageColumnLayouts.count)
        }

        for (index, layout) in messageColumnLayouts.enumerated() {
            let emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
            guard abs(emphasis - appliedRowSpacingEmphasis[index]) > 0.0005 else { continue }
            appliedRowSpacingEmphasis[index] = emphasis

            let spacing = Self.messageColumnBaseSpacing
                + Self.emphasizedMessageColumnExtraSpacing * emphasis
            layout.column.setCustomSpacing(spacing, after: layout.viewBeforeBubble)
            if layout.hasEnglish {
                layout.column.setCustomSpacing(spacing, after: layout.bubbleView)
            }
        }
    }

    private func applyBubbleEmphasisTransform(
        to bubble: DialogueJapaneseBubbleView,
        emphasis: CGFloat,
        side: DialogueSpeakerSide
    ) {
        let scale = 1 + (Self.activeBubbleScale - 1) * emphasis
        guard abs(scale - 1) > 0.001, bubble.bounds.width > 0 else {
            bubble.transform = .identity
            return
        }

        let width = bubble.bounds.width
        let dx: CGFloat
        switch side {
        case .leading:
            dx = -width * (1 - scale) / 2
        case .trailing:
            dx = width * (1 - scale) / 2
        }
        bubble.transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale)
    }

    private func applyScrollContentInsets() {
        let transportInset = max(transportBarContainer.bounds.height, 0) + Self.scrollBottomContentInsetExtra
        let topInset = presentationContext == .nestedPagingHost ? nestedPagingTopContentInset : 0
        scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: transportInset, right: 0)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: transportInset,
            right: 0
        )
    }

    // MARK: - Actions

    private func wireBubbleSwipeContentPopDeferral() {
        for container in bubbleSwipeContainers {
            container.configureContentPopGestureDeferral(from: self)
        }
    }

    private func presentSentenceFocus(forLineAt index: Int) {
        guard displayLines.indices.contains(index) else { return }
        let sentence = displayLines[index].japanese

        // Stop full-clip playback so sentence scrub owns audio while focused.
        if playbackPhase == .playing {
            pausePlayback()
        }

        let dialogueLineAudio: DialogueLineAudioReference?
        if spokenLineTexts.indices.contains(index),
           (example.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || example.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
            dialogueLineAudio = DialogueLineAudioReference(
                publishedAudioUrl: example.publishedAudioUrl,
                audioKey: example.audioKey ?? "",
                cacheMetadata: example.remoteAudioCacheMetadata,
                lineIndex: index,
                dialogueLines: spokenLineTexts
            )
        } else {
            dialogueLineAudio = nil
        }

        let scrub = SentenceScrubExperimentViewController(
            sentence: sentence,
            englishTranslation: displayLines[index].english,
            dialogueLineAudio: dialogueLineAudio
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    @objc private func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view else { return }
        let index = row.tag
        guard alignedLines.indices.contains(index) else { return }

        guard let player = makePlayer() else { return }

        let range = alignedLines[index].timeRange
        seekTargetLineIndex = index
        player.currentTime = range.lowerBound
        playbackPhase = .playing
        updateTransportControls()
        updateElapsedLabel(currentTime: range.lowerBound)
        setActiveLine(index, animated: true)
        startPlayerAfterSessionActivation(player)
    }

    /// Steps one notch along the reveal ladder, reversing at each end so swipes
    /// cycle meter → Japanese → English → Japanese → meter → …
    private func advanceRevealLevel(at index: Int, animated: Bool) {
        guard transcriptDisplayMode == .reveal,
              lineRevealLevels.indices.contains(index),
              lineRevealTravels.indices.contains(index),
              lineRevealSlots.indices.contains(index),
              japaneseLabels.indices.contains(index),
              japaneseBubbles.indices.contains(index),
              displayLines.indices.contains(index) else { return }

        let current = lineRevealLevels[index]
        let hasEnglish = lineRevealSlots[index].englishWrapper != nil
        var travel = lineRevealTravels[index]

        // Flip direction at the ends before taking the step.
        switch (current, travel) {
        case (.english, .revealing):
            travel = .concealing
        case (.japanese, .revealing) where !hasEnglish:
            // No translation — Japanese is the deepest level for this line.
            travel = .concealing
        case (.audioOnly, .concealing):
            travel = .revealing
        default:
            break
        }
        lineRevealTravels[index] = travel

        lineChangeHaptic.impactOccurred()

        switch travel {
        case .revealing:
            switch current {
            case .audioOnly:
                lineRevealLevels[index] = .japanese
                revealJapanese(at: index, animated: animated)
            case .japanese:
                guard hasEnglish else { return }
                lineRevealLevels[index] = .english
                revealEnglish(at: index, animated: animated)
            case .english:
                break
            }
        case .concealing:
            switch current {
            case .english:
                lineRevealLevels[index] = .japanese
                concealEnglish(at: index, animated: animated)
            case .japanese:
                lineRevealLevels[index] = .audioOnly
                concealJapanese(at: index, animated: animated)
            case .audioOnly:
                break
            }
        }
    }

    private func revealJapanese(at index: Int, animated: Bool) {
        let line = displayLines[index]
        let label = japaneseLabels[index]
        let bubble = japaneseBubbles[index]
        var slot = lineRevealSlots[index]

        let japaneseFont = Self.dialogueJapaneseBaseFont
        var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: japaneseFont)
        displayInsets.top += 2
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: label,
            attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                for: line.japanese,
                font: japaneseFont,
                textColor: Self.inactiveJapaneseColor
            ),
            contentInsets: displayInsets
        )

        NSLayoutConstraint.deactivate(slot.meterBubbleSizingConstraints)
        slot.textMinWidthConstraint?.isActive = true
        lineRevealSlots[index] = slot

        // Hand sizing back to the label before fading text in.
        // Meter stays parked (centered) under the text while hidden.
        label.alpha = 0
        bubble.setLabelContributesToLayout(true)
        bubble.setUnderglowConfiguration(.default)
        slot.meter.releaseToRest()

        let apply = {
            slot.meter.alpha = 0
            label.alpha = 1
            self.view.layoutIfNeeded()
            self.applyRowStylesFromEmphasis()
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            ) { _ in
                slot.meter.isHidden = true
            }
        } else {
            apply()
            slot.meter.isHidden = true
        }
    }

    private func revealEnglish(at index: Int, animated: Bool) {
        guard messageColumnLayouts.indices.contains(index) else { return }
        let slot = lineRevealSlots[index]
        guard let englishWrapper = slot.englishWrapper else { return }

        englishWrapper.isHidden = false
        messageColumnLayouts[index].hasEnglish = true

        let apply = {
            englishWrapper.alpha = 1
            self.view.layoutIfNeeded()
            self.applyMessageColumnSpacingFromEmphasis()
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            )
        } else {
            apply()
        }
    }

    private func concealEnglish(at index: Int, animated: Bool) {
        guard messageColumnLayouts.indices.contains(index) else { return }
        guard let englishWrapper = lineRevealSlots[index].englishWrapper else { return }

        messageColumnLayouts[index].hasEnglish = false

        let apply = {
            englishWrapper.alpha = 0
            self.view.layoutIfNeeded()
            self.applyMessageColumnSpacingFromEmphasis()
        }

        let finish = {
            englishWrapper.isHidden = true
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            ) { _ in
                finish()
            }
        } else {
            apply()
            finish()
        }
    }

    private func concealJapanese(at index: Int, animated: Bool) {
        let label = japaneseLabels[index]
        let bubble = japaneseBubbles[index]
        var slot = lineRevealSlots[index]
        let side = displayLines[index].speakerSide

        // Detach the label from layout first so only the meter sizes the pill.
        label.textInsets = .zero
        label.attributedText = nil
        label.alpha = 0
        bubble.setLabelContributesToLayout(false)

        slot.meter.isHidden = false
        slot.meter.alpha = 0
        slot.textMinWidthConstraint?.isActive = false
        NSLayoutConstraint.activate(slot.meterBubbleSizingConstraints)
        lineRevealSlots[index] = slot

        var glowConfig = DialogueBubbleUnderglowConfiguration.default
        glowConfig.color = side == .leading ? .blue : .yellow
        glowConfig.horizontalInset = 12
        glowConfig.blurRadius = 8
        glowConfig.offsetX = 0
        bubble.setUnderglowConfiguration(glowConfig)

        let apply = {
            slot.meter.alpha = 1
            self.view.layoutIfNeeded()
            self.applyRowStylesFromEmphasis()
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            )
        } else {
            apply()
        }
    }

    private func togglePlayPause() {
        switch playbackPhase {
        case .idle, .finished:
            startPlayback(fromBeginning: playbackPhase == .idle)
        case .playing:
            pausePlayback()
        case .paused:
            resumePlayback()
        }
    }

    private func restartTapped() {
        stopPlayback(resetPosition: true)
        startPlayback(fromBeginning: true)
    }

    private func updateTransportControls() {
        let isPlaying = playbackPhase == .playing
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.transportGlyphPointSize, weight: .semibold)
        playGlyphView.image = UIImage(
            systemName: isPlaying ? "pause.fill" : "play.fill",
            withConfiguration: symbolConfig
        )?.withRenderingMode(.alwaysTemplate)
        playGlyphView.preferredSymbolConfiguration = symbolConfig
    }

    private func updateElapsedLabel(currentTime: TimeInterval) {
        guard presentationContext == .standalone else { return }
        elapsedLabel.text = Self.formatElapsed(currentTime)
    }

    // MARK: - Builders

    private static func makeDisplayLines(for example: GrammarExample) -> [DialogueLineDisplay] {
        guard let scenario = example.scenario, !scenario.lines.isEmpty else {
            return [
                DialogueLineDisplay(
                    speaker: "Speaker",
                    speakerSide: .leading,
                    showsSpeakerLabel: true,
                    japanese: example.japanese,
                    english: example.english
                ),
            ]
        }

        var speakerSides: [String: DialogueSpeakerSide] = [:]
        var nextSide: DialogueSpeakerSide = .leading
        var previousSpeaker: String?

        return scenario.lines.map { line in
            if speakerSides[line.speaker] == nil {
                speakerSides[line.speaker] = nextSide
                nextSide = nextSide == .leading ? .trailing : .leading
            }

            let showsSpeakerLabel = line.speaker != previousSpeaker
            previousSpeaker = line.speaker

            return DialogueLineDisplay(
                speaker: line.speaker,
                speakerSide: speakerSides[line.speaker]!,
                showsSpeakerLabel: showsSpeakerLabel,
                japanese: line.japanese,
                english: line.english
            )
        }
    }

    private static func speakerPrefix(for speaker: String) -> String {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(trimmed):"
    }

    private static func insetMetadataWrapper(around label: UILabel, side: DialogueSpeakerSide) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        switch side {
        case .leading:
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
        case .trailing:
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
        }

        return wrapper
    }

    private static func metadataText(pointTitle: String, lineCount: Int, duration: TimeInterval) -> String {
        var parts = [pointTitle, "\(lineCount) lines"]
        if duration > 0 {
            parts.append(formatElapsed(duration))
        }
        return parts.joined(separator: " · ")
    }

    private static func formatElapsed(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        let hundredths = Int((clamped - floor(clamped)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    /// Shared duration for the bubble emphasis and follow-along scroll so both motions
    /// read as one gesture. Keep comfortably under the shortest line duration.
    private static let emphasisAnimationDuration: TimeInterval = 0.35
    private static let messageColumnBaseSpacing: CGFloat = 6
    /// Extra vertical gap above/below the bubble while a line is focused.
    private static let emphasizedMessageColumnExtraSpacing: CGFloat = 4
    private static let activeBubbleScale: CGFloat = 1.04

    private static let dialogueJapaneseBaseFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title2)
        return .systemFont(ofSize: base.pointSize, weight: .medium)
    }()

    private static let messageColumnMaxWidthRatio: CGFloat = 0.82
    private static let metadataHorizontalInset: CGFloat = 20
    /// Extra space kept above the active line when follow-along scrolling.
    private static let followAlongTopBuffer: CGFloat = 56
    /// Extra space kept below the active line's bottom edge when follow-along scrolling.
    private static let followAlongBottomBuffer: CGFloat = 72
    /// Breathing room between the last dialogue row and the transport bar.
    private static let scrollBottomContentInsetExtra: CGFloat = 16
    private static let inactiveJapaneseColor: UIColor = .label

    private static let englishFont: UIFont = .preferredFont(forTextStyle: .subheadline)
    private static let englishColor: UIColor = .secondaryLabel

    private func availableMessageColumnWidth() -> CGFloat {
        let margins = contentStack.layoutMargins.left + contentStack.layoutMargins.right
        let width = contentStack.bounds.width > 0 ? contentStack.bounds.width : scrollView.bounds.width
        return max(0, (width - margins) * Self.messageColumnMaxWidthRatio)
    }

    private func updateBubbleMinWidths() {
        let columnMaxWidth = availableMessageColumnWidth()
        guard columnMaxWidth > 0 else { return }
        // Text measurement costs several ms per pass; only the column width and
        // the lines themselves affect the result, so skip when neither changed.
        guard columnMaxWidth != appliedBubbleMinWidthColumnWidth else { return }
        appliedBubbleMinWidthColumnWidth = columnMaxWidth

        for (index, constraint) in bubbleMinWidthConstraints.enumerated() {
            guard displayLines.indices.contains(index) else { continue }
            constraint.constant = Self.minimumBubbleWidth(
                for: displayLines[index],
                columnMaxWidth: columnMaxWidth
            )
        }
    }

    private static func minimumBubbleWidth(
        for line: DialogueLineDisplay,
        columnMaxWidth: CGFloat
    ) -> CGFloat {
        let layoutFont = dialogueJapaneseBaseFont
        let attributed = JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
            for: line.japanese,
            font: layoutFont,
            textColor: inactiveJapaneseColor
        )
        let horizontalPadding = DialogueJapaneseBubbleView.horizontalContentPadding
        let maxTextWidth = max(0, columnMaxWidth - horizontalPadding)

        let singleLineRect = attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let wrappedRect = attributed.boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let textWidth = max(ceil(singleLineRect.width), ceil(wrappedRect.width))
        return min(columnMaxWidth, textWidth + horizontalPadding)
    }


    private static func emphasisEase(_ progress: CGFloat) -> CGFloat {
        let t = max(0, min(1, progress))
        if t < 0.5 {
            return 4 * t * t * t
        }
        return 1 - pow(-2 * t + 2, 3) / 2
    }

    private static let transportButtonSize: CGFloat = 50
    private static let transportGlyphPointSize: CGFloat = 22
    private static let transportGlyphColor = UIColor.systemYellow
    private static let nestedPagingTransportSlideDistance: CGFloat = 140

    private static func configureGlassTransportButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        glyphPointSize: CGFloat,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = transportGlyphColor
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        let glyphDimension = glyphPointSize + 4
        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: glyphDimension),
            glyphView.heightAnchor.constraint(equalToConstant: glyphDimension),
        ])
    }
}

// MARK: - Scroll: clamped offset

private extension UIScrollView {
    func clampedContentOffsetY(_ y: CGFloat, allowNoScroll: Bool) -> CGFloat? {
        let inset = adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, contentSize.height - bounds.height + inset.bottom)
        if maxY <= minY {
            if allowNoScroll { return nil }
            return minY
        }
        return min(max(y, minY), maxY)
    }

    func setClampedContentOffsetY(_ y: CGFloat, allowsScrollCallback: Bool) {
        let previousDelegate = delegate
        if !allowsScrollCallback { delegate = nil }
        let clampedY = clampedContentOffsetY(y, allowNoScroll: false) ?? y
        contentOffset = CGPoint(x: 0, y: clampedY)
        if !allowsScrollCallback { delegate = previousDelegate }
    }
}

// MARK: - Sheet presenter

enum DialogueExperimentSheetPresenter {

    static func present(
        from viewController: UIViewController,
        pointTitle: String,
        example: GrammarExample,
        animated: Bool = true
    ) {
        let dialogue = DialogueExperimentViewController(pointTitle: pointTitle, example: example)
        let nav = UINavigationController(rootViewController: dialogue)
        nav.navigationBar.prefersLargeTitles = false
        nav.modalPresentationStyle = .pageSheet
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            presentation.prefersEdgeAttachedInCompactHeight = true
            presentation.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        }
        viewController.present(nav, animated: animated)
    }

    static func presentFixture(from viewController: UIViewController, animated: Bool = true) {
        let fixture = DialogueExperimentFixture.loadExample()
        present(
            from: viewController,
            pointTitle: fixture.pointTitle,
            example: fixture.example,
            animated: animated
        )
    }
}
