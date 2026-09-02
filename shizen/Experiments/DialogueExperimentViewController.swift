//
//  DialogueExperimentViewController.swift
//  shizen
//
//  Scrollable furigana dialogue transcript in a medium/large sheet with
//  bundled scenario audio and active-line follow-along emphasis.
//

import AVFoundation
import InteractionKit
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

nonisolated enum DialogueSpeakerSide: Hashable, Sendable {
    case leading
    case trailing

    var underglowColor: DialogueBubbleUnderglowColor {
        ExperimentSettings.dialogueHighlightColor(for: self)
    }
}

struct DialogueLineDisplay {
    let speaker: String
    let speakerSide: DialogueSpeakerSide
    let showsSpeakerLabel: Bool
    let japanese: String
    let english: String?
    let stageDirection: StageDirection?
    let inlineQuestion: DialogueInlineQuestion?

    struct StageDirection: Hashable {
        let text: String
        let visibility: DialogueStageLineVisibility
    }

    var isStageLine: Bool { stageDirection != nil }
    var isInlineQuestion: Bool { inlineQuestion != nil }
    var isSpokenLine: Bool { !isStageLine && !isInlineQuestion }
}

enum DialoguePlaybackPhase {
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

class DialogueExperimentViewController: UIViewController {

    private var pointTitle: String
    private var example: GrammarExample
    private var scenarioID: String?
    private var grammarPointIDs: [String]
    private let presentationContext: DialoguePresentationContext
    private var displayLines: [DialogueLineDisplay]
    private var spokenLineTexts: [String]
    /// Maps spoken-line index → transcript display index (stage rows omitted from spoken side).
    private var spokenLineDisplayIndices: [Int] = []
    /// Maps display index → spoken-line index (`nil` for stage direction rows).
    private var displayLineSpokenIndices: [Int?] = []
    private var tokenSync: DialogueTokenSync?

    private let scrollHeaderStack = UIStackView()
    private let sceneImageContainer = UIView()
    private let sceneImageView = UIImageView()
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
    private var contentStackTopConstraint: NSLayoutConstraint?
    /// Prevents inset/constraint writes in `viewDidLayoutSubviews` from re-entering
    /// layout and overflowing the stack.
    private var isPerformingLayoutSideEffects = false
    private var lineRows: [UIView] = []
    private var japaneseBubbles: [DialogueJapaneseBubbleView] = []
    private var japaneseLabels: [FuriganaTranscriptLabel] = []
    private var englishLabels: [UILabel] = []
    /// Caption labels for stage-direction rows; `nil` for spoken lines.
    private var stageCaptionLabels: [UILabel?] = []
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
    /// English translation wrappers, hidden until swipe when ``dialogueHidesEnglishUntilSwipe``.
    private var englishWrappers: [UIView?] = []
    private var englishRevealedIndices = Set<Int>()
    /// First complete listen unlocks the scene summary.
    private var hasHeardScenario = false

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
    private let overflowButton = UIButton(type: .system)
    private let overflowGlyphView = UIImageView()
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
    /// Last emphasis used to recolor Japanese text; skip when unchanged so layout
    /// passes do not rebuild attributed strings.
    private var appliedJapaneseColorEmphasis: [CGFloat] = []
    /// Karaoke token last applied per display row (`-1` = none).
    private var appliedKaraokeTokenIndex: [Int] = []
    private var activeKaraokeTokenIndex: Int?
    private var seekTargetLineIndex: Int?
    private var playbackResumeStartedAt: CFTimeInterval = 0
    /// Invalidates in-flight async audio-session activations when a newer play
    /// request supersedes them; only the latest completion may start the player.
    private var playbackActivationGeneration = 0
    private var stageHoldGeneration = 0
    /// Spoken indices whose preceding stage lines have already been held this pass.
    private var heldStageBoundaries = Set<Int>()
    private var isHoldingForStageLine = false
    private var pendingFinishAfterStageHold = false
    /// Spoken indices whose following inline questions have already been shown this pass.
    private var heldInlineQuestionBoundaries = Set<Int>()
    private var isHoldingForInlineQuestion = false
    private var pendingFinishAfterInlineQuestion = false
    private var inlineQuestionsAfterSpokenIndex: [Int: [DialogueInlineQuestion]] = [:]
    private var pendingInlineQuestionDisplayIndices: [Int] = []
    private var pendingInlineResumeSpokenIndex: Int?
    private var inlineQuestionViews: [Int: DialogueInlineQuestionView] = [:]
    private var activeInlineQuestionView: DialogueInlineQuestionView?
    private var didHoldTrailingStageLines = false
    private var nestedPagingTopContentInset: CGFloat = 0
    private var nestedPagingTransportProgress: CGFloat = 0
    /// Set by `DialogueExperimentHarnessViewController` to print alignment / switch diagnostics.
    var alignmentDebugLog: ((String) -> Void)?
    /// Hosts (nested paging) refresh their own menus when token-sync is toggled
    /// from the transport overflow.
    var tokenSyncSettingDidChange: (() -> Void)?

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
        self.displayLines = Self.makeDisplayLines(
            for: example,
            includesStageVisibility: { $0 == .cold }
        )
        self.spokenLineTexts = GrammarExampleDialogueLines.lines(for: example)
        super.init(nibName: nil, bundle: nil)
        rebuildSpokenLineIndexMaps()
        rebuildInlineQuestionMap()
        refreshTokenSync()
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        appliedJapaneseColorEmphasis = Array(repeating: -1, count: japaneseLabels.count)
        appliedKaraokeTokenIndex = Array(repeating: -1, count: japaneseLabels.count)
        applyRowStylesFromEmphasis()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isPerformingLayoutSideEffects else { return }
        guard let contentStackTopConstraint else { return }
        isPerformingLayoutSideEffects = true
        defer { isPerformingLayoutSideEffects = false }

        playPauseButton.bringSubviewToFront(playGlyphView)
        overflowButton.bringSubviewToFront(overflowGlyphView)
        restartButton.bringSubviewToFront(restartGlyphView)
        let topConstant = dialogueContentStackTopConstant()
        if abs(contentStackTopConstraint.constant - topConstant) > 0.5 {
            contentStackTopConstraint.constant = topConstant
        }
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PlaybackAudioSession.prewarm()
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
        displayLines = makeDisplayLines(for: example)
        spokenLineTexts = GrammarExampleDialogueLines.lines(for: example)
        rebuildSpokenLineIndexMaps()
        rebuildInlineQuestionMap()
        refreshTokenSync()

        activeLineIndex = nil
        alignedLines = []
        clipDuration = 0
        audioPlayer = nil
        resolvedAudioURL = nil
        seekTargetLineIndex = nil
        playbackPhase = .idle

        hasHeardScenario = false
        englishRevealedIndices.removeAll()

        if let setting = example.scenario?.setting, !setting.isEmpty {
            settingLabel.text = setting
            applyScenarioSummaryVisibility(animated: false)
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

        if dialogueShowsScenarioChrome() {
            configureSceneImageView()
        }

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

        if dialogueShowsScenarioChrome() {
            if sceneImageView.image != nil || sceneImageURL != nil {
                scrollHeaderStack.addArrangedSubview(sceneImageContainer)
                scrollHeaderStack.setCustomSpacing(20, after: sceneImageContainer)
                // Now that container and stack share an ancestor, the width pin is safe.
                sceneImageWidthConstraint?.isActive = true
            }
            if let setting = example.scenario?.setting, !setting.isEmpty {
                scrollHeaderStack.addArrangedSubview(settingLabel)
                scrollHeaderStack.setCustomSpacing(12, after: settingLabel)
                applyScenarioSummaryVisibility(animated: false)
            }
        }
        if dialogueShowsMetadataHeader() {
            scrollHeaderStack.addArrangedSubview(metadataLabel)
        }
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
                sceneImageView.image = nil
                LessonThumbnailLoader.load(url: remoteURL, completion: finishLoading)
            }
            return
        }

        guard let image = sceneImageName.flatMap({ UIImage(named: $0) }) else {
            sceneImageContainer.isHidden = true
            return
        }
        applySceneImage(image)
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
        sceneImageView.backgroundColor = .systemGray5
        sceneImageView.layer.cornerRadius = 20
        sceneImageView.layer.cornerCurve = .continuous
        sceneImageView.layer.borderWidth = 3
        sceneImageView.layer.borderColor = UIColor.white.cgColor
        if sceneImageView.superview == nil {
            sceneImageContainer.addSubview(sceneImageView)
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
            lineCount: spokenLineTexts.count,
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

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 48
        contentStack.layoutMargins = UIEdgeInsets(
            top: 0,
            left: dialogueContentHorizontalInset(),
            bottom: 0,
            right: dialogueContentHorizontalInset()
        )
        contentStack.isLayoutMarginsRelativeArrangement = true
        // The scroll view sweeps the safe-area boundary through content near the
        // top; opting out stops per-frame margin relayout of the whole transcript.
        contentStack.insetsLayoutMarginsFromSafeArea = false
        scrollView.addSubview(contentStack)

        let topConstraint = contentStack.topAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.topAnchor,
            constant: 0
        )
        contentStackTopConstraint = topConstraint

        // Add to the view last so a layout pass cannot run with a nil top constraint.
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topConstraint,
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
            overflowButton,
            glyphView: overflowGlyphView,
            symbolName: "ellipsis",
            glyphPointSize: Self.transportGlyphPointSize - 2,
            accessibilityLabel: "More"
        )
        overflowButton.showsMenuAsPrimaryAction = true
        overflowButton.menu = makeOverflowMenu()
        overflowButton.isHidden = !dialogueShowsOverflowButton()
        overflowButton.isUserInteractionEnabled = dialogueShowsOverflowButton()

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
        leftTransportControlsStack.addArrangedSubview(overflowButton)
        leftTransportControlsStack.addArrangedSubview(restartButton)

        transportBarContainer.addSubview(leftTransportControlsStack)
        transportBarContainer.addSubview(elapsedLabel)
        transportBarContainer.addSubview(playPauseButton)

        elapsedLabel.isHidden = !dialogueShowsElapsedTime()

        let horizontalInset: CGFloat = 20
        let buttonSize = Self.transportButtonSize

        NSLayoutConstraint.activate([
            leftTransportControlsStack.leadingAnchor.constraint(equalTo: transportBarContainer.leadingAnchor, constant: horizontalInset),
            leftTransportControlsStack.topAnchor.constraint(equalTo: transportBarContainer.topAnchor, constant: 8),
            leftTransportControlsStack.bottomAnchor.constraint(equalTo: transportBarContainer.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            overflowButton.widthAnchor.constraint(equalToConstant: buttonSize),
            overflowButton.heightAnchor.constraint(equalToConstant: buttonSize),
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

    func makePlaybackSpeedMenu() -> UIMenu {
        let actions = Self.playbackSpeedOptions.map { speed in
            UIAction(
                title: Self.speedMenuTitle(for: speed),
                state: abs(speed - playbackSpeed) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.setPlaybackSpeed(speed)
            }
        }
        return UIMenu(
            title: "Playback Speed",
            image: UIImage(systemName: "gauge.with.dots.needle.67percent"),
            options: .singleSelection,
            children: actions
        )
    }

    func makeOverflowMenu() -> UIMenu {
        let rolePlay = UIAction(
            title: "Role Play",
            image: UIImage(systemName: "person.wave.2")
        ) { [weak self] _ in
            self?.presentRolePlay()
        }
        return UIMenu(children: [
            makePlaybackSpeedMenu(),
            makeTokenSyncMenuAction(),
            makeTokenSyncHighlightStyleMenu(),
            rolePlay,
        ])
    }

    func makeTokenSyncMenuAction() -> UIAction {
        UIAction(
            title: "Token sync",
            subtitle: "Yellow highlight on the spoken word",
            image: UIImage(systemName: "highlighter"),
            state: ExperimentSettings.dialogueShowsTokenSync ? .on : .off
        ) { [weak self] _ in
            self?.toggleTokenSyncHighlight()
        }
    }

    func makeTokenSyncHighlightStyleMenu() -> UIMenu {
        let selected = ExperimentSettings.dialogueTokenSyncHighlightStyle
        let actions = DialogueTokenSyncHighlightStyle.allCases.map { style in
            UIAction(
                title: style.title,
                subtitle: style.subtitle,
                state: style == selected ? .on : .off
            ) { [weak self] _ in
                self?.setTokenSyncHighlightStyle(style)
            }
        }
        return UIMenu(
            title: "Token highlight",
            image: UIImage(systemName: "paintbrush.pointed"),
            options: .singleSelection,
            children: actions
        )
    }

    func toggleTokenSyncHighlight() {
        ExperimentSettings.dialogueShowsTokenSync.toggle()
        applyTokenSyncHighlightSetting()
    }

    func setTokenSyncHighlightStyle(_ style: DialogueTokenSyncHighlightStyle) {
        ExperimentSettings.dialogueTokenSyncHighlightStyle = style
        applyTokenSyncHighlightSetting()
    }

    func applyTokenSyncHighlightSetting() {
        appliedKaraokeTokenIndex = Array(repeating: -2, count: japaneseLabels.count)
        refreshActiveKaraokeFromPlaybackTime()
        applyJapaneseLabelColorsFromEmphasis()
        dialogueRefreshOverflowMenu()
        tokenSyncSettingDidChange?()
    }

    func dialogueRefreshOverflowMenu() {
        overflowButton.menu = makeOverflowMenu()
    }

    private func presentRolePlay() {
        stopPlayback(resetPosition: false)
        let rolePlay = DialogueRolePlayViewController(
            pointTitle: pointTitle,
            example: example,
            presentationContext: .standalone,
            scenarioID: scenarioID,
            grammarPointIDs: grammarPointIDs
        )
        rolePlay.dialogueApplyPlaybackSpeed(playbackSpeed)
        if let navigationController {
            navigationController.pushViewController(rolePlay, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: rolePlay)
            nav.navigationBar.prefersLargeTitles = false
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
            present(nav, animated: true)
        }
    }

    private func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioPlayer?.enableRate = true
        if audioPlayer?.isPlaying == true {
            audioPlayer?.rate = speed
        }
        dialogueRefreshOverflowMenu()
    }

    private static func speedMenuTitle(for speed: Float) -> String {
        if abs(speed - 1.0) < 0.01 {
            return "1.0× Normal"
        }
        return String(format: "%.1f×", speed)
    }

    private func rebuildTranscriptRows() {
        setInlineQuestionFocus(nil, animated: false)
        for v in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        lineRows.removeAll()
        inlineQuestionViews.removeAll()
        activeInlineQuestionView = nil
        japaneseBubbles.removeAll()
        japaneseLabels.removeAll()
        englishLabels.removeAll()
        stageCaptionLabels.removeAll()
        listeningSpeakerSlots.removeAll()
        listeningLineMeters.removeAll()
        lineRevealLevels.removeAll()
        lineRevealTravels.removeAll()
        lineRevealSlots.removeAll()
        englishWrappers.removeAll()
        englishRevealedIndices.removeAll()
        bubbleMinWidthConstraints.removeAll()
        bubbleSwipeContainers.removeAll()
        messageColumnLayouts.removeAll()
        lineEmphasis = Array(repeating: 0, count: displayLines.count)
        appliedRowSpacingEmphasis.removeAll()
        appliedJapaneseColorEmphasis.removeAll()
        appliedBubbleMinWidthColumnWidth = -1

        contentStack.addArrangedSubview(scrollHeaderStack)
        contentStack.setCustomSpacing(dialogueHeaderBottomSpacing(), after: scrollHeaderStack)

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
                contentStack.setCustomSpacing(
                    dialogueSpacingAfterLineRow(line: line, nextLine: nextLine),
                    after: row
                )
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
        for line in displayLines where line.isSpokenLine
            && !orderedSpeakers.contains(where: { $0.speaker == line.speaker }) {
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
            // The default glow is tuned for wide text bubbles; on this small
            // pill its blur/shadow bleeds past the silhouette. Tuck it inside.
            bubble.setUnderglowConfiguration(.compactMeter(for: entry.side))

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
        for (index, bubble) in japaneseBubbles.enumerated() {
            bubble.setBackgroundStyle(.glass)
            guard displayLines.indices.contains(index), displayLines[index].isSpokenLine else {
                continue
            }
            bubble.setUnderglowConfiguration(.forSpeaker(displayLines[index].speakerSide))
        }
    }

    private func makeStageDirectionRow(text: String, index: Int) -> UIView {
        let placeholderLabel = FuriganaTranscriptLabel()
        placeholderLabel.isHidden = true
        japaneseLabels.append(placeholderLabel)

        let placeholderBubble = DialogueJapaneseBubbleView(label: placeholderLabel)
        placeholderBubble.isHidden = true
        japaneseBubbles.append(placeholderBubble)

        englishLabels.append(UILabel())
        englishWrappers.append(nil)

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.tag = index
        row.isUserInteractionEnabled = false
        row.accessibilityLabel = "Stage direction"
        row.accessibilityValue = text

        let captionLabel = UILabel()
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.numberOfLines = 0
        captionLabel.textAlignment = .center
        captionLabel.textColor = .secondaryLabel
        captionLabel.font = Self.stageDirectionFont
        captionLabel.text = text
        stageCaptionLabels.append(captionLabel)

        row.addSubview(captionLabel)
        messageColumnLayouts.append(
            LineMessageColumnLayout(
                column: UIStackView(),
                viewBeforeBubble: placeholderBubble,
                bubbleView: placeholderBubble,
                hasEnglish: false
            )
        )

        NSLayoutConstraint.activate([
            captionLabel.topAnchor.constraint(
                equalTo: row.topAnchor,
                constant: Self.stageDirectionVerticalPadding
            ),
            captionLabel.bottomAnchor.constraint(
                equalTo: row.bottomAnchor,
                constant: -Self.stageDirectionVerticalPadding
            ),
            captionLabel.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            captionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 12),
            captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
        ])

        return row
    }

    private func makeInlineQuestionRow(question: DialogueInlineQuestion, index: Int) -> UIView {
        let placeholderLabel = FuriganaTranscriptLabel()
        placeholderLabel.isHidden = true
        japaneseLabels.append(placeholderLabel)

        let placeholderBubble = DialogueJapaneseBubbleView(label: placeholderLabel)
        placeholderBubble.isHidden = true
        japaneseBubbles.append(placeholderBubble)

        englishLabels.append(UILabel())
        englishWrappers.append(nil)
        stageCaptionLabels.append(nil)
        messageColumnLayouts.append(
            LineMessageColumnLayout(
                column: UIStackView(),
                viewBeforeBubble: placeholderBubble,
                bubbleView: placeholderBubble,
                hasEnglish: false
            )
        )

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.tag = index
        row.isUserInteractionEnabled = true
        row.accessibilityLabel = "Quick check"
        row.accessibilityValue = question.prompt

        let questionView = DialogueInlineQuestionView(question: question)
        questionView.translatesAutoresizingMaskIntoConstraints = false
        questionView.onExpandedChanged = { [weak self] in
            self?.view.layoutIfNeeded()
        }
        inlineQuestionViews[index] = questionView
        row.addSubview(questionView)
        NSLayoutConstraint.activate([
            questionView.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            questionView.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            questionView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            questionView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])

        return row
    }

    private func makeLineRow(line: DialogueLineDisplay, index: Int) -> UIView {
        if let stage = line.stageDirection {
            return makeStageDirectionRow(text: stage.text, index: index)
        }
        if let question = line.inlineQuestion {
            return makeInlineQuestionRow(question: question, index: index)
        }

        stageCaptionLabels.append(nil)

        let lineContainer = DialogueLineRowView()
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
        speakerLabel.textAlignment = line.speakerSide == .trailing ? .right : .left
        speakerLabel.setContentHuggingPriority(.required, for: .horizontal)
        speakerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let speakerWrapper = Self.insetMetadataWrapper(
            around: speakerLabel,
            side: line.speakerSide,
            verticalPin: .bottom
        )
        speakerWrapper.isHidden = !line.showsSpeakerLabel

        let japaneseFont = Self.dialogueJapaneseBaseFont

        let isListeningLineMeterRow = transcriptDisplayMode == .listeningLines
        let isRevealMode = transcriptDisplayMode == .reveal
        /// Meter chrome that owns bubble sizing (listening-lines, or reveal at audio-only).
        let installsLineMeter = isListeningLineMeterRow || isRevealMode
        /// Nested paging: swipe right expands any non-listening-lines bubble.
        /// Reveal mode also wraps meter bubbles so expand + left-swipe peel work.
        let allowsBubbleSwipe = dialogueShouldInstallBubbleSwipe(
            isRevealMode: isRevealMode,
            isListeningLineMeterRow: isListeningLineMeterRow
        )

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.lineBreakMode = .byCharWrapping
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        if installsLineMeter {
            // The bubble sizes to the meter instead; keep the label empty and
            // its hugging low so it can't out-vote the meter's width.
            // Reveal mode fills the label when the line advances to Japanese.
            japaneseLabel.alpha = 0
        } else {
            japaneseLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
                to: japaneseLabel,
                text: line.japanese,
                font: japaneseFont,
                textColor: Self.inactiveJapaneseColor
            )
            DialogueContentLineWrap.applyOrphanGlue(to: japaneseLabel)
        }

        let japaneseBubble = DialogueJapaneseBubbleView(label: japaneseLabel)
        japaneseBubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        japaneseBubble.setContentCompressionResistancePriority(.required, for: .horizontal)
        japaneseBubble.setBackgroundStyle(.glass)
        japaneseBubble.setUnderglowConfiguration(.forSpeaker(line.speakerSide))

        var revealMeterBubbleSizingConstraints: [NSLayoutConstraint] = []
        var revealMeterParkConstraints: [NSLayoutConstraint] = []
        var revealMeter: AudioLevelBarsView?
        if installsLineMeter {
            // Meter owns bubble size; detach the empty label so its edge pins
            // can't fight the meter (critical when cycling back from Japanese).
            japaneseBubble.setLabelContributesToLayout(false)
            japaneseBubble.setBackgroundStyle(.glass)
            japaneseBubble.setUnderglowConfiguration(.compactMeter(for: line.speakerSide))

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
            dialogueDidInstallBubbleSwipe(swipeContainer, at: index, isRevealMode: isRevealMode)
            swipeContainer.configureContentPopGestureDeferral(from: self)
            bubbleSwipeContainers.append(swipeContainer)
            lineTapGesture.require(toFail: swipeContainer.panGestureRecognizer)
            lineContainer.swipeContainer = swipeContainer
            bubbleLayoutTarget = swipeContainer
            // Must join the column before pinning chrome to the speaker label —
            // otherwise Auto Layout has no common ancestor and crashes.
            messageColumn.addArrangedSubview(swipeContainer)
            swipeContainer.alignChromeBottom(
                to: line.showsSpeakerLabel ? speakerLabel : nil
            )
            if dialogueReservesAccessoryChromeHeight(), line.showsSpeakerLabel {
                speakerWrapper.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: DialogueBubbleSwipeRevealContainer.accessoryChromeSize
                ).isActive = true
            }
        } else {
            bubbleLayoutTarget = japaneseBubble
            messageColumn.addArrangedSubview(japaneseBubble)
        }

        speakerWrapper.widthAnchor.constraint(equalTo: bubbleLayoutTarget.widthAnchor).isActive = true
        messageColumn.setCustomSpacing(Self.messageColumnBaseSpacing, after: speakerWrapper)

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
        let hidesEnglishUntilSwipe = dialogueHidesEnglishUntilSwipe()
        let shouldBuildEnglish = (transcriptDisplayMode == .full || isRevealMode || hidesEnglishUntilSwipe)
            && !englishText.isEmpty
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
            if isRevealMode || hidesEnglishUntilSwipe {
                englishWrapper.isHidden = true
                englishWrapper.alpha = 0
                revealEnglishWrapper = englishWrapper
            } else {
                hasEnglishTranslation = true
            }
            messageColumn.addArrangedSubview(englishWrapper)
            englishLabels.append(englishLabel)
            englishWrappers.append(englishWrapper)
        } else {
            englishLabels.append(UILabel())
            englishWrappers.append(nil)
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
            let apply = {
                self.resolvedAudioURL = url
                self.prepareAudioAlignment()
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
    }

    private func prepareAudioAlignment() {
        guard let url = resolvedAudioURL else {
            return
        }

        DialogueAlignmentMetadata.readPayload(from: url) { [weak self] _ in
            guard let self, self.resolvedAudioURL == url else { return }
            self.applyAudioAlignment(url: url)
        }
    }

    private func applyAudioAlignment(url: URL) {
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

        updateTransportControls()
        if presentationContext == .standalone {
            updateElapsedLabel(currentTime: 0)
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
            cancelStageLineHold()
            cancelInlineQuestionHold()
            heldStageBoundaries = []
            heldInlineQuestionBoundaries = []
            didHoldTrailingStageLines = false
        }

        if fromBeginning, dialogueShouldHoldForStageLinesDuringPlayback() {
            let leading = stageLineDisplayIndices(beforeSpokenIndex: 0)
            if !leading.isEmpty {
                if transcriptDisplayMode == .listeningSpeakers {
                    scrollListeningBubblesIntoView()
                } else {
                    scrollToTranscriptTop(animated: true)
                }
                playbackPhase = .playing
                updateTransportControls()
                heldStageBoundaries.insert(0)
                runStageLineHold(displayIndices: leading) { [weak self] in
                    guard let self, self.playbackPhase == .playing else { return }
                    self.beginClipPlayback(player: player, fromBeginning: true, skipScroll: true)
                }
                return
            }
        }

        beginClipPlayback(player: player, fromBeginning: fromBeginning, skipScroll: false)
    }

    private func beginClipPlayback(player: AVAudioPlayer, fromBeginning: Bool, skipScroll: Bool) {
        if !skipScroll {
            if transcriptDisplayMode == .listeningSpeakers {
                scrollListeningBubblesIntoView()
            } else if fromBeginning {
                scrollToTranscriptTop(animated: true)
            }
        }

        playbackPhase = .playing
        updateTransportControls()
        syncActiveLineFromPlaybackTime(player.currentTime, animated: true)
        syncActiveTokenFromPlaybackTime(player.currentTime)
        startPlayerAfterSessionActivation(player)
    }

    /// Activates the audio session on the next main-queue turn, then starts
    /// `player`. UI flips to `.playing` immediately so line-emphasis can commit
    /// this turn; `viewDidAppear` prewarms the session so that `setActive` stays
    /// cheap. The completion no-ops if playback was paused/stopped or superseded
    /// by a newer request in the gap.
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
        if pendingFinishAfterStageHold || pendingFinishAfterInlineQuestion {
            cancelStageLineHold()
            cancelInlineQuestionHold()
            completePlaybackFinished()
            return
        }
        cancelStageLineHold()
        cancelInlineQuestionHold()
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
        cancelStageLineHold()
        cancelInlineQuestionHold()
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        seekTargetLineIndex = nil
        audioPlayer?.stop()
        if resetPosition {
            audioPlayer?.currentTime = 0
            heldStageBoundaries = []
            heldInlineQuestionBoundaries = []
            didHoldTrailingStageLines = false
            playbackPhase = .idle
            setActiveLine(nil, animated: false)
            updateElapsedLabel(currentTime: 0)
        }
        updateTransportControls()
    }

    func handlePlaybackFinished() {
        if beginTrailingInlineQuestionHoldIfNeeded() {
            return
        }
        if dialogueShouldHoldForStageLinesDuringPlayback(),
           !didHoldTrailingStageLines {
            let trailing = trailingStageLineDisplayIndices()
            if !trailing.isEmpty {
                didHoldTrailingStageLines = true
                pendingFinishAfterStageHold = true
                stopProgressDisplayLink()
                releaseListeningMetersToRest()
                playbackPhase = .playing
                updateTransportControls()
                runStageLineHold(displayIndices: trailing) { [weak self] in
                    guard let self, self.pendingFinishAfterStageHold else { return }
                    self.pendingFinishAfterStageHold = false
                    self.completePlaybackFinished()
                }
                return
            }
        }
        completePlaybackFinished()
    }

    private func completePlaybackFinished() {
        pendingFinishAfterStageHold = false
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        playbackPhase = .finished
        setActiveLine(nil, animated: true)
        updateElapsedLabel(currentTime: clipDuration)
        updateTransportControls()
        markScenarioHeardIfNeeded()
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
               !isHoldingForStageLine,
               !isHoldingForInlineQuestion,
               CACurrentMediaTime() - playbackResumeStartedAt > 0.12 {
                handlePlaybackFinished()
            }
            return
        }

        let time = player.currentTime
        updateElapsedLabel(currentTime: time)
        if dialogueShouldSyncActiveLineFromPlayback() {
            syncActiveLineFromPlaybackTime(time, animated: true)
        }
        syncActiveTokenFromPlaybackTime(time)
        dialogueDidTickPlayback(at: time)
        updateListeningMetersFromPlayback(player)
    }

    private func syncActiveLineFromPlaybackTime(_ time: TimeInterval, animated: Bool) {
        if isHoldingForStageLine || isHoldingForInlineQuestion { return }

        if let targetSpokenIndex = seekTargetLineIndex,
           alignedLines.indices.contains(targetSpokenIndex) {
            let range = alignedLines[targetSpokenIndex].timeRange
            if time + 0.05 >= range.lowerBound, time < range.upperBound + 0.05 {
                seekTargetLineIndex = nil
            } else {
                setActiveLine(displayIndex(forSpokenIndex: targetSpokenIndex), animated: false)
                return
            }
        }

        if let spokenIndex = lineIndex(for: time) {
            // Questions sit after a spoken line. Once the next line has
            // started, `spokenIndex` has already advanced — so also fire any
            // unanswered checkpoints behind the playhead.
            if beginPassedInlineQuestionHolds(beforeSpokenIndex: spokenIndex) {
                return
            }
            if alignedLines.indices.contains(spokenIndex),
               time + 0.05 >= alignedLines[spokenIndex].timeRange.upperBound,
               beginInlineQuestionHoldIfNeeded(afterSpokenIndex: spokenIndex) {
                return
            }
            if dialogueShouldHoldForStageLinesDuringPlayback() {
                let nextSpoken = spokenIndex + 1
                if alignedLines.indices.contains(spokenIndex),
                   time + 0.05 >= alignedLines[spokenIndex].timeRange.upperBound,
                   spokenLineDisplayIndices.indices.contains(nextSpoken),
                   beginStageHoldIfNeeded(beforeSpokenIndex: nextSpoken) {
                    return
                }
                if beginStageHoldIfNeeded(beforeSpokenIndex: spokenIndex) {
                    return
                }
            }
            setActiveLine(displayIndex(forSpokenIndex: spokenIndex), animated: animated)
        } else if let active = activeLineIndex,
                  displayLines.indices.contains(active),
                  displayLines[active].isStageLine {
            // Keep the opener stage line focused until speech starts.
        } else {
            setActiveLine(nil, animated: animated)
        }
    }

    private func lineIndex(for time: TimeInterval) -> Int? {
        guard !alignedLines.isEmpty else { return nil }
        var active: Int?
        for (index, line) in alignedLines.enumerated() where time >= line.timeRange.lowerBound {
            active = index
        }
        return active
    }

    private func cancelStageLineHold() {
        stageHoldGeneration += 1
        isHoldingForStageLine = false
        pendingFinishAfterStageHold = false
    }

    private func stageLineDisplayIndices(beforeSpokenIndex spokenIndex: Int) -> [Int] {
        let endDisplay = displayIndex(forSpokenIndex: spokenIndex) ?? displayLines.count
        let startDisplay: Int
        if spokenIndex <= 0 {
            startDisplay = 0
        } else if let previous = displayIndex(forSpokenIndex: spokenIndex - 1) {
            startDisplay = previous + 1
        } else {
            startDisplay = 0
        }
        guard startDisplay < endDisplay else { return [] }
        return (startDisplay..<endDisplay).filter { displayLines[$0].isStageLine }
    }

    private func trailingStageLineDisplayIndices() -> [Int] {
        guard let lastSpokenDisplay = spokenLineDisplayIndices.last else { return [] }
        guard lastSpokenDisplay + 1 < displayLines.count else { return [] }
        return ((lastSpokenDisplay + 1)..<displayLines.count).filter { displayLines[$0].isStageLine }
    }

    @discardableResult
    private func beginStageHoldIfNeeded(beforeSpokenIndex spokenIndex: Int) -> Bool {
        guard !heldStageBoundaries.contains(spokenIndex) else { return false }
        let stages = stageLineDisplayIndices(beforeSpokenIndex: spokenIndex)
        heldStageBoundaries.insert(spokenIndex)
        guard !stages.isEmpty else { return false }
        beginInterveningStageHold(beforeSpokenIndex: spokenIndex, displayIndices: stages)
        return true
    }

    private func beginInterveningStageHold(beforeSpokenIndex spokenIndex: Int, displayIndices: [Int]) {
        audioPlayer?.pause()
        runStageLineHold(displayIndices: displayIndices) { [weak self] in
            guard let self, self.playbackPhase == .playing else { return }
            if alignedLines.indices.contains(spokenIndex) {
                audioPlayer?.currentTime = alignedLines[spokenIndex].timeRange.lowerBound
            }
            if let display = displayIndex(forSpokenIndex: spokenIndex) {
                setActiveLine(display, animated: true)
            }
            guard let player = audioPlayer else { return }
            startPlayerAfterSessionActivation(player)
        }
    }

    private func runStageLineHold(displayIndices: [Int], then continueWork: @escaping () -> Void) {
        guard !displayIndices.isEmpty else {
            continueWork()
            return
        }
        isHoldingForStageLine = true
        stopProgressDisplayLink()
        presentStageHold(displayIndices: displayIndices, offset: 0, then: continueWork)
    }

    private func rebuildInlineQuestionMap() {
        inlineQuestionsAfterSpokenIndex =
            example.scenario?.inlineQuestionsAfterSpokenIndices() ?? [:]
        heldInlineQuestionBoundaries = []
        pendingInlineQuestionDisplayIndices = []
        pendingInlineResumeSpokenIndex = nil
        pendingFinishAfterInlineQuestion = false
        clearActiveInlineQuestion()
        setInlineQuestionFocus(nil, animated: false)
        let displayCount = displayLines.filter(\.isInlineQuestion).count
        print("[inline-question] transcript \(example.sourceScenarioId ?? "?") display=\(displayCount)/\(displayLines.count) map=\(inlineQuestionsAfterSpokenIndex.mapValues { $0.map(\.prompt) }) mode=\(transcriptDisplayMode)")
    }

    @discardableResult
    private func beginPassedInlineQuestionHolds(beforeSpokenIndex spokenIndex: Int) -> Bool {
        guard spokenIndex > 0 else { return false }
        for prior in 0..<spokenIndex {
            if beginInlineQuestionHoldIfNeeded(afterSpokenIndex: prior) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private func beginInlineQuestionHoldIfNeeded(afterSpokenIndex spokenIndex: Int) -> Bool {
        guard !heldInlineQuestionBoundaries.contains(spokenIndex) else { return false }
        let questions = inlineQuestionsAfterSpokenIndex[spokenIndex] ?? []
        heldInlineQuestionBoundaries.insert(spokenIndex)
        print("[inline-question] checkpoint afterSpoken=\(spokenIndex) questions=\(questions.map(\.prompt))")
        guard !questions.isEmpty else { return false }
        beginInlineQuestionHold(
            displayIndices: displayIndicesForInlineQuestions(afterSpokenIndex: spokenIndex),
            resumeSpokenIndex: spokenIndex + 1,
            finishing: false
        )
        return true
    }

    @discardableResult
    private func beginTrailingInlineQuestionHoldIfNeeded() -> Bool {
        let lastSpoken = spokenLineTexts.count - 1
        guard lastSpoken >= 0 else { return false }
        guard !heldInlineQuestionBoundaries.contains(lastSpoken) else { return false }
        let questions = inlineQuestionsAfterSpokenIndex[lastSpoken] ?? []
        heldInlineQuestionBoundaries.insert(lastSpoken)
        guard !questions.isEmpty else { return false }
        pendingFinishAfterInlineQuestion = true
        playbackPhase = .playing
        updateTransportControls()
        beginInlineQuestionHold(
            displayIndices: displayIndicesForInlineQuestions(afterSpokenIndex: lastSpoken),
            resumeSpokenIndex: lastSpoken + 1,
            finishing: true
        )
        return true
    }

    private func displayIndicesForInlineQuestions(afterSpokenIndex spokenIndex: Int) -> [Int] {
        let start: Int
        if spokenIndex < 0 {
            start = 0
        } else if let spokenDisplay = displayIndex(forSpokenIndex: spokenIndex) {
            start = spokenDisplay + 1
        } else {
            return []
        }
        var indices: [Int] = []
        var index = start
        while index < displayLines.count, !displayLines[index].isSpokenLine {
            if displayLines[index].isInlineQuestion {
                indices.append(index)
            }
            index += 1
        }
        return indices
    }

    private func beginInlineQuestionHold(
        displayIndices: [Int],
        resumeSpokenIndex: Int,
        finishing: Bool
    ) {
        audioPlayer?.pause()
        isHoldingForInlineQuestion = true
        pendingFinishAfterInlineQuestion = finishing
        pendingInlineQuestionDisplayIndices = displayIndices
        pendingInlineResumeSpokenIndex = resumeSpokenIndex
        stopProgressDisplayLink()
        releaseListeningMetersToRest()
        presentNextInlineQuestion()
    }

    private func presentNextInlineQuestion() {
        clearActiveInlineQuestion()
        guard let displayIndex = pendingInlineQuestionDisplayIndices.first else {
            finishInlineQuestionHold()
            return
        }
        pendingInlineQuestionDisplayIndices.removeFirst()
        guard let questionView = inlineQuestionViews[displayIndex] else {
            presentNextInlineQuestion()
            return
        }
        activeInlineQuestionView = questionView
        questionView.onContinue = { [weak self] in
            self?.presentNextInlineQuestion()
        }
        questionView.onAnswered = { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.scrollLineIntoView(at: displayIndex, animated: true)
        }
        setActiveLine(displayIndex, animated: true)
        setInlineQuestionFocus(displayIndex, animated: true)
        questionView.prepareForHold()
    }

    private func finishInlineQuestionHold() {
        clearActiveInlineQuestion()
        isHoldingForInlineQuestion = false
        setInlineQuestionFocus(nil, animated: true)
        let finishing = pendingFinishAfterInlineQuestion
        let resumeSpoken = pendingInlineResumeSpokenIndex
        pendingFinishAfterInlineQuestion = false
        pendingInlineResumeSpokenIndex = nil
        pendingInlineQuestionDisplayIndices = []

        guard playbackPhase == .playing else { return }
        if finishing || resumeSpoken == nil || !alignedLines.indices.contains(resumeSpoken!) {
            handlePlaybackFinished()
            return
        }
        audioPlayer?.currentTime = alignedLines[resumeSpoken!].timeRange.lowerBound
        if let display = displayIndex(forSpokenIndex: resumeSpoken!) {
            setActiveLine(display, animated: true)
        }
        guard let player = audioPlayer else { return }
        startPlayerAfterSessionActivation(player)
    }

    private func cancelInlineQuestionHold() {
        pendingInlineQuestionDisplayIndices = []
        pendingInlineResumeSpokenIndex = nil
        pendingFinishAfterInlineQuestion = false
        isHoldingForInlineQuestion = false
        clearActiveInlineQuestion()
        setInlineQuestionFocus(nil, animated: true)
    }

    private func clearActiveInlineQuestion() {
        activeInlineQuestionView?.onContinue = nil
        activeInlineQuestionView?.onAnswered = nil
        activeInlineQuestionView = nil
    }

    /// Dims everything except the active quick check so the checkpoint can
    /// be read without the surrounding dialogue competing for attention.
    private func setInlineQuestionFocus(_ focusedIndex: Int?, animated: Bool) {
        let fade: CGFloat = 0.4
        let updates = {
            self.scrollHeaderStack.alpha = focusedIndex == nil ? 1 : fade
            self.scrollHeaderStack.isUserInteractionEnabled = focusedIndex == nil
            for (index, row) in self.lineRows.enumerated() {
                let keep = focusedIndex == nil || focusedIndex == index
                row.alpha = keep ? 1 : fade
                row.isUserInteractionEnabled = keep
            }
            for view in self.contentStack.arrangedSubviews {
                if view === self.scrollHeaderStack { continue }
                if self.lineRows.contains(where: { $0 === view }) { continue }
                view.alpha = focusedIndex == nil ? 1 : fade
                view.isUserInteractionEnabled = focusedIndex == nil
            }
        }

        if animated {
            UIView.animate(
                withDuration: Self.emphasisAnimationDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                updates()
            }
        } else {
            updates()
        }
    }

    private func presentStageHold(
        displayIndices: [Int],
        offset: Int,
        then continueWork: @escaping () -> Void
    ) {
        let generation = stageHoldGeneration
        guard displayIndices.indices.contains(offset) else {
            isHoldingForStageLine = false
            continueWork()
            return
        }
        setActiveLine(displayIndices[offset], animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stageLineHold) { [weak self] in
            guard let self, self.stageHoldGeneration == generation, self.isHoldingForStageLine else { return }
            self.presentStageHold(displayIndices: displayIndices, offset: offset + 1, then: continueWork)
        }
    }

    private func refreshTokenSync() {
        tokenSync = DialogueTokenSync.validated(
            example.tokenSync,
            spokenTexts: spokenLineTexts,
            publishedContentHash: example.publishedContentHash
        )
        activeKaraokeTokenIndex = nil
        appliedKaraokeTokenIndex = Array(repeating: -1, count: japaneseLabels.count)
    }

    private func refreshActiveKaraokeFromPlaybackTime(_ time: TimeInterval? = nil) {
        guard ExperimentSettings.dialogueShowsTokenSync,
              let tokenSync,
              let displayIndex = activeLineIndex,
              let spokenIndex = spokenIndex(forDisplayIndex: displayIndex) else {
            activeKaraokeTokenIndex = nil
            return
        }
        let t = time ?? audioPlayer?.currentTime ?? 0
        activeKaraokeTokenIndex = tokenSync.tokenIndex(lineIndex: spokenIndex, at: t)
    }

    private func syncActiveTokenFromPlaybackTime(_ time: TimeInterval) {
        let previous = activeKaraokeTokenIndex
        refreshActiveKaraokeFromPlaybackTime(time)
        guard activeKaraokeTokenIndex != previous else { return }
        applyJapaneseLabelColorsFromEmphasis()
    }

    // MARK: - Active line

    private func setActiveLine(_ newIndex: Int?, animated: Bool) {
        guard newIndex != activeLineIndex else { return }

        if let alignmentDebugLog {
            let time = audioPlayer?.currentTime ?? 0
            let from = activeLineIndex.map(String.init) ?? "nil"
            let to = newIndex.map(String.init) ?? "nil"
            var detail = "line switch at t=\(String(format: "%.3f", time))s: \(from) → \(to)"
            if let newIndex,
               let spokenIndex = spokenIndex(forDisplayIndex: newIndex),
               alignedLines.indices.contains(spokenIndex) {
                let range = alignedLines[spokenIndex].timeRange
                detail += " (bounds ≥\(String(format: "%.3f", range.lowerBound)) <\(String(format: "%.3f", range.upperBound)))"
                detail += " \"\(alignedLines[spokenIndex].text)\""
            } else if let newIndex, displayLines.indices.contains(newIndex), displayLines[newIndex].isStageLine {
                detail += " (stage direction)"
            } else if let newIndex, displayLines.indices.contains(newIndex), displayLines[newIndex].isInlineQuestion {
                detail += " (inline question)"
            } else if newIndex != nil {
                detail += " WARNING: index out of alignedLines range (count=\(alignedLines.count))"
            }
            alignmentDebugLog(detail)
        }

        if newIndex != nil {
            lineChangeHaptic.impactOccurred()
        }

        activeLineIndex = newIndex
        refreshActiveKaraokeFromPlaybackTime()

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

    /// Follow-along target: the full line including English, so the translation
    /// is not left under the bottom-bar blur.
    private func followAlongTargetFrame(at index: Int) -> CGRect? {
        guard lineRows.indices.contains(index) else { return nil }
        let row = lineRows[index]
        guard !row.isHidden, row.bounds.height > 0 else { return nil }

        var frame = rowBoundsInScrollableContent(row)
        if messageColumnLayouts.indices.contains(index),
           messageColumnLayouts[index].hasEnglish,
           englishLabels.indices.contains(index) {
            let label = englishLabels[index]
            if let wrapper = label.superview, !wrapper.isHidden, wrapper.bounds.height > 0 {
                frame = frame.union(contentStack.convert(wrapper.bounds, from: wrapper))
            }
        }
        return frame
    }

    private func followAlongBuffers(for index: Int) -> (top: CGFloat, bottom: CGFloat) {
        if displayLines.indices.contains(index),
           (displayLines[index].isStageLine || displayLines[index].isInlineQuestion) {
            return (Self.stageFollowAlongTopBuffer, Self.stageFollowAlongBottomBuffer)
        }
        return (Self.followAlongTopBuffer, Self.followAlongBottomBuffer)
    }

    /// Which way the transcript must scroll so the line at `index` sits inside the
    /// top/bottom follow-along margins, or `nil` when it is already comfortably visible.
    private func followAlongDirection(revealingLineAt index: Int) -> FollowAlongScrollDirection? {
        scrollView.layoutIfNeeded()
        guard let rowFrame = followAlongTargetFrame(at: index) else { return nil }

        let inset = scrollView.adjustedContentInset
        let currentY = scrollView.contentOffset.y
        let buffers = followAlongBuffers(for: index)
        let visibleBottom = currentY + scrollView.bounds.height - inset.bottom - buffers.bottom
        let visibleTop = currentY + buffers.top

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
        guard let rowFrame = followAlongTargetFrame(at: index) else { return nil }
        let inset = scrollView.adjustedContentInset
        let buffers = followAlongBuffers(for: index)
        let targetY: CGFloat
        switch direction {
        case .down:
            targetY = rowFrame.maxY - scrollView.bounds.height + inset.bottom + buffers.bottom
        case .up:
            targetY = rowFrame.minY - buffers.top
        }
        return scrollView.clampedContentOffsetY(targetY, allowNoScroll: true)
    }

    /// Scrolls so the line — through the bottom of its English — clears the
    /// bottom bar. Safe to call when the active index did not change.
    func scrollLineIntoView(at index: Int, animated: Bool) {
        guard lineRows.indices.contains(index) else { return }
        scrollView.layoutIfNeeded()
        guard !scrollView.isTracking, !scrollView.isDecelerating else { return }
        guard let direction = followAlongDirection(revealingLineAt: index) else { return }

        if animated, emphasisAnimationLink != nil {
            if followAlongScrollDirection == nil {
                followAlongScrollStartY = scrollView.contentOffset.y
            }
            followAlongScrollDirection = direction
            return
        }

        guard let endY = followAlongEndOffsetY(revealingLineAt: index, direction: direction) else { return }
        guard abs(endY - scrollView.contentOffset.y) >= 1 else { return }
        if animated {
            UIView.animate(
                withDuration: Self.emphasisAnimationDuration,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.scrollView.setClampedContentOffsetY(endY, allowsScrollCallback: false)
            }
        } else {
            scrollView.setClampedContentOffsetY(endY, allowsScrollCallback: false)
        }
    }

    /// Focus is conveyed by the bubble transform scale, underglow, row spacing,
    /// and Japanese text color (secondary → label) — font size stays put so
    /// focused lines never re-wrap.
    private func applyRowStylesFromEmphasis() {
        for (i, bubble) in japaneseBubbles.enumerated() {
            guard displayLines.indices.contains(i), displayLines[i].isSpokenLine else { continue }
            let emphasis = lineEmphasis.indices.contains(i) ? lineEmphasis[i] : 0
            // Meter-only bubbles keep an underglow floor so inactive speaker /
            // line meters don't go fully dark.
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
        applyJapaneseLabelColorsFromEmphasis()
        applyMessageColumnSpacingFromEmphasis()
        applyStageLineRowSpacingFromEmphasis()
        applyStageLineEmphasisFromEmphasis()
    }

    private func applyJapaneseLabelColorsFromEmphasis() {
        if appliedJapaneseColorEmphasis.count != japaneseLabels.count {
            appliedJapaneseColorEmphasis = Array(repeating: -1, count: japaneseLabels.count)
        }
        if appliedKaraokeTokenIndex.count != japaneseLabels.count {
            appliedKaraokeTokenIndex = Array(repeating: -1, count: japaneseLabels.count)
        }

        for (index, label) in japaneseLabels.enumerated() {
            guard dialogueShouldApplyEmphasisTextColor(at: index) else {
                appliedJapaneseColorEmphasis[index] = -1
                appliedKaraokeTokenIndex[index] = -1
                continue
            }
            guard let attributed = label.attributedText, attributed.length > 0 else { continue }
            let emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
            let karaokeToken = karaokeTokenIndex(forDisplayIndex: index)
            let highlightStyleBit = ExperimentSettings.dialogueTokenSyncHighlightStyle == .full ? 10_000 : 0
            let glowBit = japaneseBubbles.indices.contains(index)
                ? japaneseBubbles[index].currentUnderglowConfiguration.color.rawValue * 100_000
                : 0
            let karaokeKey = (karaokeToken ?? -1) + highlightStyleBit + glowBit
            guard abs(emphasis - appliedJapaneseColorEmphasis[index]) > 0.0005
                    || karaokeKey != appliedKaraokeTokenIndex[index] else { continue }
            appliedJapaneseColorEmphasis[index] = emphasis
            appliedKaraokeTokenIndex[index] = karaokeKey
            let baseColor = japaneseColor(forEmphasis: emphasis)
            if let karaokeToken,
               let spoken = spokenIndex(forDisplayIndex: index),
               let range = tokenSync?.utf16Range(
                lineIndex: spoken,
                tokenIndex: karaokeToken,
                inDisplay: attributed.string
               ) {
                let highlightColor = japaneseBubbles.indices.contains(index)
                    ? japaneseBubbles[index].tokenHighlightColor
                    : FuriganaTranscriptLabel.tokenSyncHighlightColor
                label.setTokenHighlightPreservingLayout(
                    foregroundColor: baseColor,
                    highlightedRange: range,
                    fullHeight: ExperimentSettings.dialogueTokenSyncHighlightStyle == .full,
                    highlightColor: highlightColor
                )
            } else {
                label.setForegroundColorPreservingLayout(baseColor)
            }
        }
    }

    private func karaokeTokenIndex(forDisplayIndex index: Int) -> Int? {
        guard ExperimentSettings.dialogueShowsTokenSync,
              tokenSync != nil,
              index == activeLineIndex else { return nil }
        return activeKaraokeTokenIndex
    }

    private func japaneseColor(forEmphasis emphasis: CGFloat) -> UIColor {
        if emphasis <= 0.001 { return Self.inactiveJapaneseColor }
        if emphasis >= 0.999 { return Self.activeJapaneseColor }
        let from = Self.inactiveJapaneseColor.resolvedColor(with: traitCollection)
        let to = Self.activeJapaneseColor.resolvedColor(with: traitCollection)
        return from.mixed(with: to, amount: emphasis)
    }

    /// Same emphasis channel as spoken bubbles: scale the caption from center
    /// and lift the type from secondary to label.
    private func applyStageLineEmphasisFromEmphasis() {
        for (index, label) in stageCaptionLabels.enumerated() {
            guard let label else { continue }
            let emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
            let scale = 1 + (Self.activeBubbleScale - 1) * emphasis
            label.transform = abs(scale - 1) > 0.001
                ? CGAffineTransform(scaleX: scale, y: scale)
                : .identity
            label.textColor = japaneseColor(forEmphasis: emphasis)
        }
    }

    /// Opens extra stack space above and below a focused stage line so it can
    /// sit in a clear band while the 0.75s hold asks you to read the scene.
    private func applyStageLineRowSpacingFromEmphasis() {
        guard lineRows.count == displayLines.count, displayLines.count > 1 else { return }
        for index in displayLines.indices.dropLast() {
            let line = displayLines[index]
            let next = displayLines[index + 1]
            guard !line.isSpokenLine || !next.isSpokenLine else { continue }
            let emphasis = max(
                !line.isSpokenLine && lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0,
                !next.isSpokenLine && lineEmphasis.indices.contains(index + 1) ? lineEmphasis[index + 1] : 0
            )
            let spacing = dialogueSpacingAfterLineRow(line: line, nextLine: next)
                + Self.stageLineFocusExtraSpacing * emphasis
            contentStack.setCustomSpacing(spacing, after: lineRows[index])
        }
    }

    private func applyMessageColumnSpacingFromEmphasis() {
        if appliedRowSpacingEmphasis.count != messageColumnLayouts.count {
            appliedRowSpacingEmphasis = Array(repeating: -1, count: messageColumnLayouts.count)
        }

        for (index, layout) in messageColumnLayouts.enumerated() {
            guard displayLines.indices.contains(index), displayLines[index].isSpokenLine else { continue }
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
        let transform: CGAffineTransform
        if abs(scale - 1) > 0.001, bubble.bounds.width > 0 {
            let width = bubble.bounds.width
            let dx: CGFloat
            switch side {
            case .leading:
                dx = -width * (1 - scale) / 2
            case .trailing:
                dx = width * (1 - scale) / 2
            }
            transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale)
        } else {
            transform = .identity
        }

        if let container = bubble.superview as? DialogueBubbleSwipeRevealContainer {
            container.setBaseBubbleTransform(transform)
        } else {
            bubble.transform = transform
        }
    }

    private func applyScrollContentInsets() {
        let transportInset = max(transportBarContainer.bounds.height, 0) + Self.scrollBottomContentInsetExtra
        let topInset = dialogueScrollTopContentInset()
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: transportInset, right: 0)
        guard scrollView.contentInset != insets else { return }
        scrollView.contentInset = insets
        scrollView.verticalScrollIndicatorInsets = insets
    }

    // MARK: - Actions

    private func wireBubbleSwipeContentPopDeferral() {
        for container in bubbleSwipeContainers {
            container.configureContentPopGestureDeferral(from: self)
        }
    }

    func dialogueShouldInstallBubbleSwipe(isRevealMode: Bool, isListeningLineMeterRow: Bool) -> Bool {
        !isListeningLineMeterRow
    }

    /// When true, the speaker-name row is at least as tall as Role Play mic/Hear
    /// chrome so those buttons sit in-row instead of overflowing (and clipping).
    func dialogueReservesAccessoryChromeHeight() -> Bool { false }

    func dialogueDidInstallBubbleSwipe(
        _ container: DialogueBubbleSwipeRevealContainer,
        at index: Int,
        isRevealMode: Bool
    ) {
        container.onCommit = { [weak self] in
            self?.presentSentenceFocus(forLineAt: index)
        }
        if displayLines.indices.contains(index) {
            container.chromeEdge = displayLines[index].speakerSide == .leading
                ? .trailing
                : .leading
        }
        if isRevealMode {
            container.allowsProgressiveReveal = true
            container.onProgressiveRevealCommit = { [weak self] in
                self?.advanceRevealLevel(at: index, animated: true)
            }
        } else if dialogueHidesEnglishUntilSwipe(), lineHasEnglishTranslation(at: index) {
            container.allowsProgressiveReveal = true
            container.progressiveRevealAccessibilityHint = "swipe left to show or hide English"
            container.onProgressiveRevealCommit = { [weak self] in
                self?.toggleEnglishReveal(at: index, animated: true)
            }
        }
    }

    func presentSentenceFocus(forLineAt index: Int) {
        guard displayLines.indices.contains(index), displayLines[index].isSpokenLine else { return }
        let sentence = displayLines[index].japanese

        // Stop full-clip playback so sentence scrub owns audio while focused.
        if playbackPhase == .playing {
            pausePlayback()
        }

        let spokenIndex = spokenIndex(forDisplayIndex: index)
        let dialogueLineAudio: DialogueLineAudioReference?
        if let spokenIndex,
           spokenLineTexts.indices.contains(spokenIndex),
           (example.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || example.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
            dialogueLineAudio = DialogueLineAudioReference(
                publishedAudioUrl: example.publishedAudioUrl,
                audioKey: example.audioKey ?? "",
                cacheMetadata: example.remoteAudioCacheMetadata,
                lineIndex: spokenIndex,
                dialogueLines: spokenLineTexts
            )
        } else {
            dialogueLineAudio = nil
        }

        let tokens = spokenIndex.flatMap { tokenSync?.japaneseTokens(lineIndex: $0, in: sentence) }

        let scrub = SentenceScrubExperimentViewController(
            sentence: sentence,
            englishTranslation: displayLines[index].english,
            dialogueLineAudio: dialogueLineAudio,
            dialogueContext: nuanceContext(forDisplayIndex: index),
            tokens: tokens
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    private func nuanceContext(forDisplayIndex index: Int) -> DialogueNuanceContext? {
        var lines: [DialogueNuanceContext.Line] = []
        var focusedOffset: Int?
        for (displayIndex, line) in displayLines.enumerated() {
            guard !line.isStageLine else { continue }
            let japanese = line.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !japanese.isEmpty else { continue }
            if displayIndex == index {
                focusedOffset = lines.count
            }
            lines.append(
                DialogueNuanceContext.Line(
                    speaker: line.speaker,
                    japanese: japanese,
                    english: line.english
                )
            )
        }
        guard let focusedOffset else { return nil }
        return DialogueNuanceContext.around(lines: lines, focusedIndex: focusedOffset)
    }

    @objc func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view else { return }
        let index = row.tag
        if displayLines.indices.contains(index), displayLines[index].isInlineQuestion {
            presentInlineQuestion(atDisplayIndex: index)
            return
        }
        playLine(at: index)
    }

    private func presentInlineQuestion(atDisplayIndex displayIndex: Int) {
        guard displayLines.indices.contains(displayIndex),
              displayLines[displayIndex].isInlineQuestion else { return }
        let previousSpoken = (0..<displayIndex)
            .reversed()
            .compactMap { spokenIndex(forDisplayIndex: $0) }
            .first
        if let previousSpoken {
            heldInlineQuestionBoundaries.insert(previousSpoken)
        }
        let resumeSpoken = (previousSpoken ?? -1) + 1
        if playbackPhase == .playing {
            beginInlineQuestionHold(
                displayIndices: [displayIndex],
                resumeSpokenIndex: resumeSpoken,
                finishing: !alignedLines.indices.contains(resumeSpoken)
            )
            return
        }
        pendingInlineQuestionDisplayIndices = [displayIndex]
        pendingInlineResumeSpokenIndex = nil
        pendingFinishAfterInlineQuestion = false
        isHoldingForInlineQuestion = true
        presentNextInlineQuestion()
    }

    func playLine(at displayIndex: Int) {
        guard let spokenIndex = spokenIndex(forDisplayIndex: displayIndex) else { return }
        guard alignedLines.indices.contains(spokenIndex) else { return }
        guard dialogueShouldAllowLineTap(at: displayIndex) else { return }

        guard let player = makePlayer() else { return }

        cancelStageLineHold()
        cancelInlineQuestionHold()
        for index in 0...spokenIndex {
            heldStageBoundaries.insert(index)
            heldInlineQuestionBoundaries.insert(index)
        }

        let range = alignedLines[spokenIndex].timeRange
        seekTargetLineIndex = spokenIndex
        player.currentTime = range.lowerBound
        playbackPhase = .playing
        updateTransportControls()
        updateElapsedLabel(currentTime: range.lowerBound)
        setActiveLine(displayIndex, animated: true)
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
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: label,
            text: line.japanese,
            font: japaneseFont,
            textColor: Self.inactiveJapaneseColor
        )
        DialogueContentLineWrap.applyOrphanGlue(to: label)

        NSLayoutConstraint.deactivate(slot.meterBubbleSizingConstraints)
        slot.textMinWidthConstraint?.isActive = true
        lineRevealSlots[index] = slot

        // Hand sizing back to the label before fading text in.
        // Meter stays parked (centered) under the text while hidden.
        label.alpha = 0
        bubble.setLabelContributesToLayout(true)
        bubble.setUnderglowConfiguration(.forSpeaker(line.speakerSide))
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

        // Hide inside the animation so UIStackView collapses the English slot
        // with the same layout pass as the alpha fade — deferring `isHidden`
        // to completion made rows below jump into place.
        let apply = {
            englishWrapper.alpha = 0
            englishWrapper.isHidden = true
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

        bubble.setUnderglowConfiguration(.compactMeter(for: side))

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

    private func lineHasEnglishTranslation(at index: Int) -> Bool {
        guard displayLines.indices.contains(index) else { return false }
        let text = displayLines[index].english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty
    }

    private func toggleEnglishReveal(at index: Int, animated: Bool) {
        guard englishWrappers.indices.contains(index),
              englishWrappers[index] != nil else { return }
        if englishRevealedIndices.contains(index) {
            concealEnglishTranslation(at: index, animated: animated)
        } else {
            revealEnglishTranslation(at: index, animated: animated)
        }
    }

    private func revealEnglishTranslation(at index: Int, animated: Bool) {
        guard messageColumnLayouts.indices.contains(index),
              englishWrappers.indices.contains(index),
              let englishWrapper = englishWrappers[index] else { return }

        englishRevealedIndices.insert(index)
        englishWrapper.isHidden = false
        messageColumnLayouts[index].hasEnglish = true

        let apply = {
            englishWrapper.alpha = 1
            self.view.layoutIfNeeded()
            self.applyMessageColumnSpacingFromEmphasis()
        }

        if animated {
            lineChangeHaptic.impactOccurred()
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            ) { _ in
                self.scrollLineIntoView(at: index, animated: true)
            }
        } else {
            apply()
        }
    }

    private func concealEnglishTranslation(at index: Int, animated: Bool) {
        guard messageColumnLayouts.indices.contains(index),
              englishWrappers.indices.contains(index),
              let englishWrapper = englishWrappers[index] else { return }

        englishRevealedIndices.remove(index)
        messageColumnLayouts[index].hasEnglish = false

        // Hide inside the animation so UIStackView collapses the English slot
        // with the same layout pass as the alpha fade — deferring `isHidden`
        // to completion made rows below jump into place.
        let apply = {
            englishWrapper.alpha = 0
            englishWrapper.isHidden = true
            self.view.layoutIfNeeded()
            self.applyMessageColumnSpacingFromEmphasis()
        }

        if animated {
            lineChangeHaptic.impactOccurred()
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

    private func applyScenarioSummaryVisibility(animated: Bool) {
        let setting = example.scenario?.setting?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldShow = dialogueShowsScenarioChrome()
            && !setting.isEmpty
            && (!dialogueHidesSummaryUntilHeard() || hasHeardScenario)
        let apply = {
            self.settingLabel.isHidden = !shouldShow
            self.settingLabel.alpha = shouldShow ? 1 : 0
            if self.contentStackTopConstraint != nil, !self.isPerformingLayoutSideEffects {
                self.view.layoutIfNeeded()
            }
        }
        if shouldShow {
            settingLabel.isHidden = false
        }
        if animated, view.window != nil {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
                animations: apply
            ) { _ in
                self.settingLabel.isHidden = !shouldShow
            }
        } else {
            apply()
        }
    }

    private func markScenarioHeardIfNeeded() {
        guard !hasHeardScenario else { return }
        hasHeardScenario = true
        applyScenarioSummaryVisibility(animated: true)
    }

    func togglePlayPause() {
        switch playbackPhase {
        case .idle, .finished:
            startPlayback(fromBeginning: true)
        case .playing:
            pausePlayback()
        case .paused:
            resumePlayback()
        }
    }

    func restartTapped() {
        stopPlayback(resetPosition: true)
        startPlayback(fromBeginning: true)
    }

    func dialoguePlayPauseSymbolName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    func dialoguePlayPauseAccessibilityLabel(isPlaying: Bool) -> String {
        isPlaying ? "Pause" : "Play"
    }

    func dialogueDidTickPlayback(at time: TimeInterval) {}

    func dialogueShouldAllowLineTap(at index: Int) -> Bool {
        guard displayLines.indices.contains(index), displayLines[index].isSpokenLine else { return false }
        return true
    }

    /// Role Play keeps completed / in-progress match colors out of the
    /// secondary → label emphasis interpolation.
    func dialogueShouldApplyEmphasisTextColor(at index: Int) -> Bool { true }

    func dialogueShowsScenarioChrome() -> Bool { true }

    func dialogueShowsMetadataHeader() -> Bool { true }

    func dialogueHeaderBottomSpacing() -> CGFloat { 64 }

    /// Vertical gap between consecutive transcript rows. Role Play overrides to
    /// clear accessory chrome that sits above the bubble.
    func dialogueSpacingAfterLineRow(
        line: DialogueLineDisplay,
        nextLine: DialogueLineDisplay
    ) -> CGFloat {
        if !line.isSpokenLine || !nextLine.isSpokenLine { return Self.stageLineRowSpacing }
        return nextLine.speaker == line.speaker ? 20 : 48
    }

    func dialogueScrollTopContentInset() -> CGFloat {
        presentationContext == .nestedPagingHost ? nestedPagingTopContentInset : 0
    }

    func dialogueContentStackTopConstant() -> CGFloat { 8 }

    func dialogueContentHorizontalInset() -> CGFloat { 24 }

    func dialogueShouldSyncActiveLineFromPlayback() -> Bool { true }

    /// Pause the clip and focus each stage direction for ``stageLineHold``
    /// before the next spoken line. Role Play sequences its own holds.
    func dialogueShouldHoldForStageLinesDuringPlayback() -> Bool { true }

    func dialogueShowsElapsedTime() -> Bool {
        presentationContext == .standalone
    }

    /// Hide play when the clip is missing — a clear in-app signal that audio
    /// still needs to be generated for this dialogue.
    func dialogueShowsPlayButton() -> Bool {
        resolvedAudioURL != nil
    }

    func dialogueShowsOverflowButton() -> Bool { true }

    /// Japanese is the default; English is a left-swipe.
    func dialogueHidesEnglishUntilSwipe() -> Bool {
        transcriptDisplayMode == .full
    }

    /// Scene-setting copy would give away the dialogue before you hear it.
    func dialogueHidesSummaryUntilHeard() -> Bool { true }

    func updateTransportControls() {
        let isPlaying = playbackPhase == .playing
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.transportGlyphPointSize, weight: .semibold)
        playGlyphView.image = UIImage(
            systemName: dialoguePlayPauseSymbolName(isPlaying: isPlaying),
            withConfiguration: symbolConfig
        )?.withRenderingMode(.alwaysTemplate)
        playGlyphView.preferredSymbolConfiguration = symbolConfig
        playPauseButton.accessibilityLabel = dialoguePlayPauseAccessibilityLabel(isPlaying: isPlaying)
        let showPlay = dialogueShowsPlayButton()
        playPauseButton.isHidden = !showPlay
        playPauseButton.isUserInteractionEnabled = showPlay
        let showOverflow = dialogueShowsOverflowButton()
        overflowButton.isHidden = !showOverflow
        overflowButton.isUserInteractionEnabled = showOverflow
    }

    private func updateElapsedLabel(currentTime: TimeInterval) {
        guard dialogueShowsElapsedTime() else { return }
        elapsedLabel.text = Self.formatElapsed(currentTime)
    }

    /// Cold listen shows `cold` stage lines; practice-only stage lines are omitted.
    func dialogueIncludesStageLineVisibility(_ visibility: DialogueStageLineVisibility) -> Bool {
        visibility == .cold
    }

    private func makeDisplayLines(for example: GrammarExample) -> [DialogueLineDisplay] {
        Self.makeDisplayLines(
            for: example,
            includesStageVisibility: { [weak self] visibility in
                self?.dialogueIncludesStageLineVisibility(visibility) ?? (visibility == .cold)
            }
        )
    }

    private func rebuildSpokenLineIndexMaps() {
        var spokenToDisplay: [Int] = []
        var spokenForDisplay: [Int?] = []
        var spokenCounter = 0
        for (displayIndex, line) in displayLines.enumerated() {
            if !line.isSpokenLine {
                spokenForDisplay.append(nil)
            } else {
                spokenToDisplay.append(displayIndex)
                spokenForDisplay.append(spokenCounter)
                spokenCounter += 1
            }
        }
        spokenLineDisplayIndices = spokenToDisplay
        displayLineSpokenIndices = spokenForDisplay
    }

    func spokenIndex(forDisplayIndex displayIndex: Int) -> Int? {
        guard displayLineSpokenIndices.indices.contains(displayIndex) else { return nil }
        return displayLineSpokenIndices[displayIndex]
    }

    func displayIndex(forSpokenIndex spokenIndex: Int) -> Int? {
        guard spokenLineDisplayIndices.indices.contains(spokenIndex) else { return nil }
        return spokenLineDisplayIndices[spokenIndex]
    }

    // MARK: - Builders

    private static func makeDisplayLines(
        for example: GrammarExample,
        includesStageVisibility: (DialogueStageLineVisibility) -> Bool
    ) -> [DialogueLineDisplay] {
        guard let scenario = example.scenario, !scenario.lines.isEmpty else {
            return [
                DialogueLineDisplay(
                    speaker: "Speaker",
                    speakerSide: .leading,
                    showsSpeakerLabel: true,
                    japanese: example.japanese,
                    english: example.english,
                    stageDirection: nil,
                    inlineQuestion: nil
                ),
            ]
        }

        var speakerSides: [String: DialogueSpeakerSide] = [:]
        var nextSide: DialogueSpeakerSide = .leading
        var previousSpeaker: String?
        var result: [DialogueLineDisplay] = []

        for line in scenario.lines {
            if let question = line.inlineQuestion {
                print("[inline-question] display-row +\(result.count) \(example.sourceScenarioId ?? "?") \(question.prompt)")
                result.append(
                    DialogueLineDisplay(
                        speaker: "",
                        speakerSide: .leading,
                        showsSpeakerLabel: false,
                        japanese: "",
                        english: nil,
                        stageDirection: nil,
                        inlineQuestion: question
                    )
                )
                continue
            }
            if let visibility = line.stageVisibility {
                guard includesStageVisibility(visibility) else { continue }
                result.append(
                    DialogueLineDisplay(
                        speaker: "",
                        speakerSide: .leading,
                        showsSpeakerLabel: false,
                        japanese: "",
                        english: nil,
                        stageDirection: .init(text: line.japanese, visibility: visibility),
                        inlineQuestion: nil
                    )
                )
                continue
            }

            if speakerSides[line.speaker] == nil {
                speakerSides[line.speaker] = nextSide
                nextSide = nextSide == .leading ? .trailing : .leading
            }

            let showsSpeakerLabel = line.speaker != previousSpeaker
            previousSpeaker = line.speaker

            result.append(
                DialogueLineDisplay(
                    speaker: line.speaker,
                    speakerSide: speakerSides[line.speaker]!,
                    showsSpeakerLabel: showsSpeakerLabel,
                    japanese: line.japanese,
                    english: line.english,
                    stageDirection: nil,
                    inlineQuestion: nil
                )
            )
        }

        return result
    }

    private static func speakerPrefix(for speaker: String) -> String {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(trimmed):"
    }

    private enum MetadataVerticalPin {
        /// Label fills the wrapper (english under a bubble).
        case fill
        /// Label sits on the wrapper's bottom edge so a taller header (role-play
        /// controls) still keeps the name on the bubble.
        case bottom
    }

    private static func insetMetadataWrapper(
        around label: UILabel,
        side: DialogueSpeakerSide,
        verticalPin: MetadataVerticalPin = .fill
    ) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        var constraints: [NSLayoutConstraint] = []
        switch (side, verticalPin) {
        case (.leading, .fill):
            constraints += [
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ]
        case (.trailing, .fill):
            constraints += [
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            ]
        case (.leading, .bottom):
            constraints += [
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            ]
            let hugTop = label.topAnchor.constraint(equalTo: wrapper.topAnchor)
            hugTop.priority = .defaultHigh
            constraints.append(hugTop)
        case (.trailing, .bottom):
            constraints += [
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
            ]
            let hugTop = label.topAnchor.constraint(equalTo: wrapper.topAnchor)
            hugTop.priority = .defaultHigh
            constraints.append(hugTop)
        }

        NSLayoutConstraint.activate(constraints)
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

    /// Pause after a stage direction so the scene can land before the next line.
    private static let stageLineHold: TimeInterval = 0.75

    /// Shared duration for the bubble emphasis, follow-along scroll, and
    /// quick-check focus fade so those motions read as one gesture.
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
    /// Extra space kept below the English (or bubble) so it clears the bottom
    /// transport bar and its edge-effect blur.
    private static let followAlongBottomBuffer: CGFloat = 100
    /// Stage directions need a wider empty band so the scene can be read
    /// without a bubble crowding the caption.
    private static let stageFollowAlongTopBuffer: CGFloat = 88
    private static let stageFollowAlongBottomBuffer: CGFloat = 136
    /// Inner padding on the stage-direction caption itself.
    private static let stageDirectionVerticalPadding: CGFloat = 24
    /// Stack gap before/after a stage row (larger than a speaker change).
    private static let stageLineRowSpacing: CGFloat = 52
    /// Extra stack gap opened while a stage line is focused.
    private static let stageLineFocusExtraSpacing: CGFloat = 24
    /// Must be at least ``followAlongBottomBuffer`` so the last revealed line can
    /// actually scroll that far above the transport bar.
    private static let scrollBottomContentInsetExtra: CGFloat = 100
    private static let inactiveJapaneseColor: UIColor = .secondaryLabel
    private static let activeJapaneseColor: UIColor = .label

    private static let englishFont: UIFont = .preferredFont(forTextStyle: .subheadline)
    private static let englishColor: UIColor = .secondaryLabel

    private static let stageDirectionFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        guard let italicDescriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return base
        }
        return UIFont(descriptor: italicDescriptor, size: base.pointSize)
    }()

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

        var constraintIndex = 0
        for (lineIndex, line) in displayLines.enumerated() {
            guard line.isSpokenLine else { continue }
            if japaneseLabels.indices.contains(lineIndex),
               japaneseBubbles.indices.contains(lineIndex) {
                let textWidth = max(
                    0,
                    columnMaxWidth - japaneseBubbles[lineIndex].layoutHorizontalContentPadding
                )
                japaneseLabels[lineIndex].preferredMaxLayoutWidth = textWidth
                japaneseLabels[lineIndex].invalidateIntrinsicContentSize()
                japaneseBubbles[lineIndex].invalidateIntrinsicContentSize()
            }
            guard bubbleMinWidthConstraints.indices.contains(constraintIndex) else { continue }
            bubbleMinWidthConstraints[constraintIndex].constant = Self.minimumBubbleWidth(
                for: line,
                columnMaxWidth: columnMaxWidth
            )
            constraintIndex += 1
        }
    }

    private static func minimumBubbleWidth(
        for line: DialogueLineDisplay,
        columnMaxWidth: CGFloat
    ) -> CGFloat {
        guard line.isSpokenLine else { return 0 }
        let layoutFont = dialogueJapaneseBaseFont
        let attributed = DialogueContentLineWrap.preparingForLayout(
            JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                for: line.japanese,
                font: layoutFont,
                textColor: inactiveJapaneseColor
            )
        )
        let horizontalPadding = DialogueJapaneseBubbleView.horizontalContentPadding
        let maxTextWidth = max(0, columnMaxWidth - horizontalPadding)
        // Measure after wrapping so a hanging-punctuation break can shrink
        // the bubble to the longest line instead of the column cap.
        let usedWidth = ceil(
            JapaneseFuriganaBuilder.usedBaseTextWidth(
                for: attributed,
                limitingWidth: maxTextWidth
            )
        )
        return min(columnMaxWidth, usedWidth + horizontalPadding)
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

// MARK: - Role-play subclass API

extension DialogueExperimentViewController {
    func dialogueRebuildDisplayLines() {
        displayLines = makeDisplayLines(for: example)
        spokenLineTexts = GrammarExampleDialogueLines.lines(for: example)
        rebuildSpokenLineIndexMaps()
        rebuildInlineQuestionMap()
        refreshTokenSync()
    }

    var dialogueDisplayLines: [DialogueLineDisplay] { displayLines }
    var dialogueAlignedLines: [AlignedTimeLine] { alignedLines }
    var dialogueJapaneseLabels: [FuriganaTranscriptLabel] { japaneseLabels }
    var dialogueJapaneseBubbles: [DialogueJapaneseBubbleView] { japaneseBubbles }
    var dialoguePlaybackPhase: DialoguePlaybackPhase { playbackPhase }

    func dialogueMessageColumn(at index: Int) -> UIStackView? {
        guard messageColumnLayouts.indices.contains(index) else { return nil }
        return messageColumnLayouts[index].column
    }

    func dialogueBubbleLayoutView(at index: Int) -> UIView? {
        guard messageColumnLayouts.indices.contains(index) else { return nil }
        return messageColumnLayouts[index].bubbleView
    }

    func dialogueViewBeforeBubble(at index: Int) -> UIView? {
        guard messageColumnLayouts.indices.contains(index) else { return nil }
        return messageColumnLayouts[index].viewBeforeBubble
    }
    var dialogueSeekTargetLineIndex: Int? {
        get { seekTargetLineIndex }
        set { seekTargetLineIndex = newValue }
    }

    static var dialogueJapaneseFont: UIFont { dialogueJapaneseBaseFont }
    static var dialogueInactiveJapaneseColor: UIColor { inactiveJapaneseColor }

    func dialogueJapaneseColor(forLineAt index: Int) -> UIColor {
        let emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
        return japaneseColor(forEmphasis: emphasis)
    }

    func dialogueSetActiveLine(_ index: Int?, animated: Bool) {
        setActiveLine(index, animated: animated)
    }

    func dialoguePausePlayback() {
        pausePlayback()
    }

    func dialogueResumePlayback() {
        resumePlayback()
    }

    func dialogueMakePlayer() -> AVAudioPlayer? {
        makePlayer()
    }

    func dialogueStartPlayerAfterSessionActivation(_ player: AVAudioPlayer) {
        startPlayerAfterSessionActivation(player)
    }

    func dialogueUpdateTransportControls() {
        updateTransportControls()
    }

    func dialogueUpdateElapsedLabel(currentTime: TimeInterval) {
        updateElapsedLabel(currentTime: currentTime)
    }

    func dialogueStopPlayback(resetPosition: Bool) {
        stopPlayback(resetPosition: resetPosition)
    }

    func dialogueSetPlaybackPhase(_ phase: DialoguePlaybackPhase) {
        playbackPhase = phase
    }

    func dialogueApplyPlaybackSpeed(_ speed: Float) {
        setPlaybackSpeed(speed)
    }

    /// Drops `accessory` into the transport bar's empty center, squeezed between
    /// the leading controls and play/pause.
    func dialogueInstallTransportCenterView(_ accessory: UIView) {
        accessory.translatesAutoresizingMaskIntoConstraints = false
        transportBarContainer.addSubview(accessory)
        NSLayoutConstraint.activate([
            accessory.centerXAnchor.constraint(equalTo: transportBarContainer.centerXAnchor),
            accessory.centerYAnchor.constraint(equalTo: leftTransportControlsStack.centerYAnchor),
            accessory.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftTransportControlsStack.trailingAnchor,
                constant: 10
            ),
            accessory.trailingAnchor.constraint(
                lessThanOrEqualTo: playPauseButton.leadingAnchor,
                constant: -10
            ),
        ])
        transportBarContainer.bringSubviewToFront(accessory)
    }

    var dialoguePlayerCurrentTime: TimeInterval? {
        audioPlayer?.currentTime
    }

    var dialogueLineRows: [UIView] { lineRows }
    var dialogueBubbleSwipeContainers: [DialogueBubbleSwipeRevealContainer] { bubbleSwipeContainers }

    func dialogueWireBubbleSwipeContentPopDeferral() {
        wireBubbleSwipeContentPopDeferral()
    }

    func dialogueSetTransportBarHidden(_ hidden: Bool) {
        transportBarContainer.isHidden = hidden
        transportBarContainer.isUserInteractionEnabled = !hidden
    }

    func dialogueMarkScenarioCompleted() {
        guard let scenarioID else { return }
        DialogueProgressStore.shared.markCompleted(scenarioID: scenarioID)
        GrammarMasteryStore.shared.recordEncounter(
            grammarIDs: grammarPointIDs,
            scenarioID: scenarioID
        )
    }
}

// MARK: - Scroll: clamped offset

private extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        let t = min(max(amount, 0), 1)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}

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
