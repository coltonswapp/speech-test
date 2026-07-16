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

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var contentStackTopConstraint: NSLayoutConstraint!
    private var lineRows: [UIView] = []
    private var japaneseBubbles: [DialogueJapaneseBubbleView] = []
    private var japaneseLabels: [FuriganaTranscriptLabel] = []
    private var englishLabels: [UILabel] = []
    private var bubbleMinWidthConstraints: [NSLayoutConstraint] = []
    private var appliedBubbleMinWidthColumnWidth: CGFloat = -1
    private var bubbleSwipeContainers: [DialogueBubbleSwipeRevealContainer] = []
    private var messageColumnLayouts: [LineMessageColumnLayout] = []
    private let lineChangeHaptic = UIImpactFeedbackGenerator(style: .light)

    private struct LineMessageColumnLayout {
        let column: UIStackView
        let viewBeforeBubble: UIView
        let bubbleView: UIView
        let hasEnglish: Bool
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
    /// Emphasis value each row's Japanese text was last rendered with; re-rendering
    /// furigana is expensive, so unchanged rows are skipped.
    private var appliedRowTextEmphasis: [CGFloat] = []
    private var seekTargetLineIndex: Int?
    private var playbackResumeStartedAt: CFTimeInterval = 0
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
            sceneImageWidthConstraint = sceneImageContainer.widthAnchor.constraint(
                equalTo: scrollHeaderStack.widthAnchor,
                multiplier: 0.92
            )
        }
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
            sceneImageWidthConstraint = sceneImageContainer.widthAnchor.constraint(
                equalTo: scrollHeaderStack.widthAnchor,
                multiplier: 0.92
            )
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
        bubbleMinWidthConstraints.removeAll()
        bubbleSwipeContainers.removeAll()
        messageColumnLayouts.removeAll()
        lineEmphasis = Array(repeating: 0, count: displayLines.count)
        appliedRowTextEmphasis.removeAll()
        appliedBubbleMinWidthColumnWidth = -1

        contentStack.addArrangedSubview(scrollHeaderStack)
        contentStack.setCustomSpacing(64, after: scrollHeaderStack)

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
        applyBubbleBackgroundStyleToAllBubbles()
        syncLineEmphasisToActiveIndex(animated: false)
        applyRowStylesFromEmphasis()
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

        let japaneseFont = Self.dialogueJapaneseFont(emphasis: 0)

        var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: japaneseFont)
        displayInsets.top += 2

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                for: line.japanese,
                font: japaneseFont,
                textColor: Self.inactiveJapaneseColor
            ),
            contentInsets: displayInsets
        )

        let japaneseBubble = DialogueJapaneseBubbleView(label: japaneseLabel)
        japaneseBubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        japaneseBubble.setContentCompressionResistancePriority(.required, for: .horizontal)

        let minBubbleWidth = Self.minimumBubbleWidth(
            for: line,
            columnMaxWidth: availableMessageColumnWidth()
        )

        messageColumn.addArrangedSubview(speakerWrapper)

        let bubbleLayoutTarget: UIView
        if presentationContext == .nestedPagingHost {
            let swipeContainer = DialogueBubbleSwipeRevealContainer(bubbleView: japaneseBubble)
            swipeContainer.hostScrollView = scrollView
            swipeContainer.onCommit = { [weak self] in
                self?.presentSentenceFocus(forLineAt: index)
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

        let minBubbleWidthConstraint = bubbleLayoutTarget.widthAnchor.constraint(
            greaterThanOrEqualToConstant: minBubbleWidth
        )
        minBubbleWidthConstraint.priority = .required
        minBubbleWidthConstraint.isActive = true
        bubbleMinWidthConstraints.append(minBubbleWidthConstraint)

        japaneseLabels.append(japaneseLabel)
        japaneseBubbles.append(japaneseBubble)

        var hasEnglishTranslation = false
        if let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines), !english.isEmpty {
            hasEnglishTranslation = true
            let englishLabel = UILabel()
            englishLabel.font = Self.englishFont
            englishLabel.textColor = Self.englishColor
            englishLabel.numberOfLines = 0
            englishLabel.textAlignment = line.speakerSide == .trailing ? .right : .left
            englishLabel.text = english
            let englishWrapper = Self.insetMetadataWrapper(
                around: englishLabel,
                side: line.speakerSide
            )
            messageColumn.addArrangedSubview(englishWrapper)
            englishLabels.append(englishLabel)
        } else {
            englishLabels.append(UILabel())
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
            audioKey: example.audioKey
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

        do {
            try PlaybackAudioSession.activateForPlayback()
        } catch {
            return
        }

        seekTargetLineIndex = nil

        if fromBeginning {
            player.currentTime = 0
            scrollToTranscriptTop(animated: true)
        }

        playbackResumeStartedAt = CACurrentMediaTime()
        player.play()
        applyPlaybackSpeedToPlayer()
        playbackPhase = .playing
        startProgressDisplayLink()
        updateTransportControls()
        syncActiveLineFromPlaybackTime(player.currentTime, animated: true)
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        playbackPhase = .paused
        stopProgressDisplayLink()
        updateTransportControls()
    }

    private func resumePlayback() {
        guard let player = audioPlayer else { return }
        seekTargetLineIndex = nil
        playbackResumeStartedAt = CACurrentMediaTime()
        player.play()
        applyPlaybackSpeedToPlayer()
        playbackPhase = .playing
        startProgressDisplayLink()
        updateTransportControls()
    }

    private func stopPlayback(resetPosition: Bool) {
        stopProgressDisplayLink()
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
        playbackPhase = .finished
        setActiveLine(nil, animated: true)
        updateElapsedLabel(currentTime: clipDuration)
        updateTransportControls()
        recordScenarioCompletionIfNeeded()
    }

    private func recordScenarioCompletionIfNeeded() {
        guard let scenarioID else { return }
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

    private func applyRowStylesFromEmphasis() {
        if appliedRowTextEmphasis.count != japaneseBubbles.count {
            appliedRowTextEmphasis = Array(repeating: -1, count: japaneseBubbles.count)
        }

        for (i, bubble) in japaneseBubbles.enumerated() {
            let emphasis = lineEmphasis.indices.contains(i) ? lineEmphasis[i] : 0
            let line = displayLines[i]

            // Re-rendering furigana text costs several ms per row; only the emphasis
            // affects the rendered string, so skip rows where it hasn't moved.
            if abs(emphasis - appliedRowTextEmphasis[i]) > 0.0005 {
                appliedRowTextEmphasis[i] = emphasis
                let japaneseFont = Self.dialogueJapaneseFont(emphasis: emphasis)
                let textColor = Self.japaneseTextColor(emphasis: emphasis, backgroundStyle: .glass)

                var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: japaneseFont)
                displayInsets.top += 2
                JapaneseFuriganaBuilder.applyScrubDisplay(
                    to: japaneseLabels[i],
                    attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                        for: line.japanese,
                        font: japaneseFont,
                        textColor: textColor
                    ),
                    contentInsets: displayInsets
                )
            }

            bubble.setEmphasis(emphasis)
            applyBubbleEmphasisTransform(
                to: bubble,
                emphasis: emphasis,
                side: line.speakerSide
            )
        }
        applyMessageColumnSpacingFromEmphasis()
    }

    private func applyMessageColumnSpacingFromEmphasis() {
        for (index, layout) in messageColumnLayouts.enumerated() {
            let emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
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
        let transportInset = max(transportBarContainer.bounds.height, 0)
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
                lineIndex: index,
                dialogueLines: spokenLineTexts
            )
        } else {
            dialogueLineAudio = nil
        }

        let scrub = SentenceScrubExperimentViewController(
            sentence: sentence,
            dialogueLineAudio: dialogueLineAudio
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    @objc private func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view else { return }
        let index = row.tag
        guard alignedLines.indices.contains(index) else { return }

        guard let player = makePlayer() else { return }
        do {
            try PlaybackAudioSession.activateForPlayback()
        } catch {
            return
        }

        let range = alignedLines[index].timeRange
        seekTargetLineIndex = index
        player.currentTime = range.lowerBound
        playbackResumeStartedAt = CACurrentMediaTime()
        player.play()
        applyPlaybackSpeedToPlayer()
        playbackPhase = .playing
        startProgressDisplayLink()
        updateTransportControls()
        updateElapsedLabel(currentTime: range.lowerBound)
        setActiveLine(index, animated: true)
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
    private static let activeJapaneseColor: UIColor = .white
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
        let layoutFont = dialogueJapaneseFont(emphasis: 1)
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

    private static func dialogueJapaneseFont(emphasis: CGFloat) -> UIFont {
        let amount = max(0, min(1, emphasis))
        let minWeight = UIFont.Weight.medium.rawValue
        let maxWeight = UIFont.Weight.bold.rawValue
        let weightValue = minWeight + (maxWeight - minWeight) * amount
        return .systemFont(ofSize: dialogueJapaneseBaseFont.pointSize, weight: UIFont.Weight(weightValue))
    }

    private static func japaneseTextColor(
        emphasis: CGFloat,
        backgroundStyle: DialogueBubbleBackgroundStyle
    ) -> UIColor {
        switch backgroundStyle {
        case .solid:
            return blendColors(from: inactiveJapaneseColor, to: activeJapaneseColor, amount: emphasis)
        case .glass:
            return inactiveJapaneseColor
        }
    }

    private static func emphasisEase(_ progress: CGFloat) -> CGFloat {
        let t = max(0, min(1, progress))
        if t < 0.5 {
            return 4 * t * t * t
        }
        return 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func blendColors(from start: UIColor, to end: UIColor, amount: CGFloat) -> UIColor {
        let t = max(0, min(1, amount))
        var sr: CGFloat = 0
        var sg: CGFloat = 0
        var sb: CGFloat = 0
        var sa: CGFloat = 0
        var er: CGFloat = 0
        var eg: CGFloat = 0
        var eb: CGFloat = 0
        var ea: CGFloat = 0
        start.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        end.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        return UIColor(
            red: sr + (er - sr) * t,
            green: sg + (eg - sg) * t,
            blue: sb + (eb - sb) * t,
            alpha: sa + (ea - sa) * t
        )
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
