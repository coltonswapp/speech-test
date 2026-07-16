//
//  KanaSpellingViewController.swift
//  shizen
//
//  DEBUG experiment: tap kana tiles to spell a target word (animated into a spelling row).
//


import UIKit

private extension UIAction.Identifier {
    static let kanaGridTap = UIAction.Identifier("kanaSpelling.gridTap")
    static let kanaSpellingTap = UIAction.Identifier("kanaSpelling.spellingTap")
}

// MARK: - Motion constants

private enum KanaSpellingMotion {
    // Duration ladder (snappy local UI)
    static let settleDuration: TimeInterval = 0.08
    static let snapDuration: TimeInterval = 0.14
    static let slideDuration: TimeInterval = 0.18
    /// Long-distance flight — fast launch, ease into the slot (no sluggish ease-in at the start).
    static let flightDuration: TimeInterval = 0.17
    static let flightTiming = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.25, y: 1),
        controlPoint2: CGPoint(x: 0.35, y: 1)
    )
    static let highlightDuration: TimeInterval = 0.18
    /// Background + border fade-in when a tile lands in the spelling row.
    static let landingHighlightDuration: TimeInterval = 0.11
    static let landingSettleDuration: TimeInterval = 0.06

    // Spring roles
    static let settleDamping: CGFloat = 0.88
    static let settleVelocity: CGFloat = 0.35
    static let landingSettleDamping: CGFloat = 0.82
    static let landingSettleVelocity: CGFloat = 0.55

    static let arrivalSettleScale: CGFloat = 0.96

    /// Pause after a correct check before the success tile cascade begins.
    static let successCheckDelay: TimeInterval = 0.22

    /// Delay between each tile's bounce start in the success cascade.
    static let successCascadeStagger: TimeInterval = 0.09

    /// Keyframe time (0–1) in the first tile's bounce when the success chime fires.
    static func successChimeKeyTime(forSyllableCount count: Int) -> TimeInterval {
        KanaSoundMatchMetrics.successChimeKeyTime
    }

    /// Two-tile words use `chime2`; start the chime slightly before the first bounce launches.
    static let spellingTwoTileChimeLead: TimeInterval = 0.04

    static func successChimeLead(forSyllableCount count: Int) -> TimeInterval {
        count == 2 ? spellingTwoTileChimeLead : 0
    }

    static let pressScale: CGFloat = 0.94
    static let pressDownDuration: TimeInterval = 0.075
    static let pressUpDuration: TimeInterval = 0.12
    static let pressUpDamping: CGFloat = 0.72

    /// Horizontal wiggle when a checked answer is wrong.
    static let incorrectShakeDuration: TimeInterval = 0.42
    static let incorrectShakeDisplacement: CGFloat = 10

    /// Start compacting the spelling row while the returning tile is still in flight.
    static let returnRowShiftDelay: TimeInterval = 0.06
    static let returnSlideDuration: TimeInterval = 0.14

    /// Hold before spelling-row reorder drag begins.
    static let reorderPressDuration: TimeInterval = 0.18
    static let reorderAllowableMovement: CGFloat = 14
}

private final class KanaSpellingReorderGestureRecognizer: UILongPressGestureRecognizer {}

// MARK: - Tile

private final class KanaSpellingTile: UIControl {

    enum Highlight {
        case normal
        case selected
        case correct
    }

    let kana: String
    var homeGridIndex: Int?
    private let kanaLabel = UILabel()
    private var currentHighlight: Highlight = .normal
    private var isPressScaled = false

    private static let normalBackground = ExperimentPalette.cardSurface
    private static let normalBorder = ExperimentPalette.cardBorder
    private static let selectedBackground = ExperimentPalette.highlightFill
    private static let selectedBorder = ExperimentPalette.highlightBorder
    private static let correctBackground = ExperimentPalette.successFill
    private static let correctBorder = ExperimentPalette.successBorder

    init(kana: String) {
        self.kana = kana
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHighlight(_ highlight: Highlight, animated: Bool = false) {
        currentHighlight = highlight
        let target = appearance(for: highlight)
        let apply = { self.applyAppearance(target) }
        guard animated else {
            apply()
            return
        }
        UIView.animate(
            withDuration: KanaSpellingMotion.highlightDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            apply()
        }
    }

    /// Scale settle plus a cream fill and gold border that grow in on landing.
    func animateLandingSelection(scaleBounce: Bool = true, completion: (() -> Void)? = nil) {
        isPressScaled = false
        layer.removeAllAnimations()

        let selected = appearance(for: .selected)
        currentHighlight = .selected

        if scaleBounce {
            applyAppearance(appearance(for: .normal))
            transform = CGAffineTransform(
                scaleX: KanaSpellingMotion.arrivalSettleScale,
                y: KanaSpellingMotion.arrivalSettleScale
            )
            layer.borderColor = selected.borderColor?.resolvedColor(with: traitCollection).cgColor

            UIView.animate(
                withDuration: KanaSpellingMotion.landingHighlightDuration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.backgroundColor = selected.backgroundColor
                self.layer.borderWidth = selected.borderWidth
            }

            UIView.animate(
                withDuration: KanaSpellingMotion.landingSettleDuration,
                delay: 0,
                usingSpringWithDamping: KanaSpellingMotion.landingSettleDamping,
                initialSpringVelocity: KanaSpellingMotion.landingSettleVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = .identity
            } completion: { _ in
                completion?()
            }
        } else {
            transform = .identity
            UIView.animate(
                withDuration: KanaSpellingMotion.landingHighlightDuration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.applyAppearance(selected)
            } completion: { _ in
                completion?()
            }
        }
    }

    /// Clears press-scale state so flight snapshots start from a neutral transform.
    func cancelPressFeedback() {
        isPressScaled = false
        layer.removeAllAnimations()
        transform = .identity
    }

    private struct TileAppearance {
        var backgroundColor: UIColor
        var borderWidth: CGFloat
        var borderColor: UIColor?
    }

    private func appearance(for highlight: Highlight) -> TileAppearance {
        switch highlight {
        case .normal:
            TileAppearance(
                backgroundColor: Self.normalBackground,
                borderWidth: ExperimentCardStroke.normalWidth,
                borderColor: Self.normalBorder
            )
        case .selected:
            TileAppearance(
                backgroundColor: Self.selectedBackground,
                borderWidth: ExperimentCardStroke.emphasisWidth,
                borderColor: Self.selectedBorder
            )
        case .correct:
            TileAppearance(
                backgroundColor: Self.correctBackground,
                borderWidth: ExperimentCardStroke.emphasisWidth,
                borderColor: Self.correctBorder
            )
        }
    }

    private func applyAppearance(_ appearance: TileAppearance) {
        backgroundColor = appearance.backgroundColor
        layer.borderWidth = appearance.borderWidth
        // Resolve against the live trait collection so dark/light switches don't get stuck.
        layer.borderColor = appearance.borderColor?.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance(appearance(for: currentHighlight))
    }

    /// Green highlight plus the shared kana success bounce (used in the success cascade).
    func animateCorrectJump(
        successSound: ExperimentFeedbackSound.PreparedSuccessSound? = nil,
        successChimeKeyTime: TimeInterval? = nil,
        completion: (() -> Void)? = nil
    ) {
        setHighlight(.correct, animated: false)
        animateKanaSoundMatchBounce(
            configuration: .production,
            successSound: successSound,
            successChimeKeyTime: successChimeKeyTime,
            completion: completion
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: ExperimentCardStroke.choiceCornerRadius
        ).cgPath
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        layer.cornerRadius = ExperimentCardStroke.choiceCornerRadius
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        setHighlight(.normal)

        kanaLabel.text = kana
        kanaLabel.textAlignment = .center
        kanaLabel.isUserInteractionEnabled = false
        kanaLabel.adjustsFontForContentSizeCategory = true
        kanaLabel.adjustsFontSizeToFitWidth = true
        kanaLabel.minimumScaleFactor = 0.5
        let metrics = UIFontMetrics(forTextStyle: .title1)
        kanaLabel.font = metrics.scaledFont(
            for: .systemFont(ofSize: KanaSpellingViewController.kanaFontSize, weight: .semibold)
        )
        kanaLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(kanaLabel)
        NSLayoutConstraint.activate([
            kanaLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            kanaLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            kanaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            kanaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            widthAnchor.constraint(equalToConstant: KanaSpellingViewController.tileWidth),
            heightAnchor.constraint(equalToConstant: KanaSpellingViewController.tileHeight),
        ])

        accessibilityLabel = kana
        setupPressFeedback()
    }

    private func setupPressFeedback() {
        addTarget(self, action: #selector(pressTouchDown), for: .touchDown)
        addTarget(self, action: #selector(pressTouchUp), for: .touchUpInside)
        addTarget(self, action: #selector(pressTouchUp), for: .touchUpOutside)
        addTarget(self, action: #selector(pressTouchUp), for: .touchCancel)
        addTarget(self, action: #selector(pressTouchUp), for: .touchDragExit)
    }

    @objc private func pressTouchDown() {
        guard isEnabled, !isHidden else { return }
        ExperimentFeedbackSound.playClick()
        isPressScaled = true
        UIView.animate(
            withDuration: KanaSpellingMotion.pressDownDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = CGAffineTransform(
                scaleX: KanaSpellingMotion.pressScale,
                y: KanaSpellingMotion.pressScale
            )
        }
    }

    @objc private func pressTouchUp() {
        guard isPressScaled else { return }
        isPressScaled = false
        UIView.animate(
            withDuration: KanaSpellingMotion.pressUpDuration,
            delay: 0,
            usingSpringWithDamping: KanaSpellingMotion.pressUpDamping,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        }
    }
}

// MARK: - View controller

class KanaSpellingViewController: LessonStepViewController, UIGestureRecognizerDelegate {

    var onStepResult: (([String], Bool) -> Void)?

    fileprivate static let tileWidth: CGFloat = 64
    fileprivate static let tileHeight: CGFloat = 78
    fileprivate static let kanaFontSize: CGFloat = 28
    fileprivate static let spellingSlotSpacing: CGFloat = 8
    private static let gridSpacing: CGFloat = 11
    private static let instructionToWordSpacing: CGFloat = 16
    private static let wordToSpellingSpacing: CGFloat = 24
    private static let spellingRowToLineSpacing: CGFloat = 10
    private static let replayButtonSize: CGFloat = 50
    private static let replayButtonSpacing: CGFloat = 12
    private static let spellingLineHorizontalPadding: CGFloat = 48

    private static let gridColumns = 4

    private var gridRows: Int
    private var gridCellCount: Int

    private let promptStyle: KanaSpellingPromptStyle
    private let script: KanaScript
    private var currentWordIndex: Int
    private var totalSteps: Int
    private var challenge: (hiragana: String, romaji: String, meaning: String)
    private var targetSyllables: [String]
    private var didAutoPlayChallenge = false

    private enum CTAMode {
        case check
        case next
    }

    private let meaningLabel = UILabel()
    private let targetLabel = UILabel()
    private let promptTextStack = UIStackView()
    private let targetWordContainer = UIView()
    private let spellingRowWrapper = UIView()
    private let spellingLineWrapper = UIView()
    private let replayControl = LessonAudioReplayButton(
        size: 50,
        glyphPointSize: 22,
        glyphDimension: 26
    )
    private var ctaMode: CTAMode = .check
    private let spellingLine = UIView()
    private let spellingRowContainer = UIView()
    private let spellingStack = UIStackView()
    private let gridStack = UIStackView()

    private var spellingSlots: [UIView] = []
    private var spellingSlotTiles: [KanaSpellingTile?]
    private var gridRowStacks: [UIStackView] = []
    /// Placeholder views holding grid layout open while a tile is in the spelling row.
    private var gridPlaceholders: [UIView?]
    private var hasSucceeded = false
    private var successCascadeGeneration = 0
    private let pronunciationPlayer = KanaPronunciationPlayer()
    private var returnLayoutWorkItem: DispatchWorkItem?

    private let spellingReorderRecognizer = KanaSpellingReorderGestureRecognizer()
    private weak var dragTile: KanaSpellingTile?
    private weak var dragFlyer: UIView?
    private weak var dragSlotPlaceholder: UIView?
    private var dragTouchOffset: CGPoint = .zero
    private var dragCurrentIndex: Int?
    /// Slots kept visible while tiles fly back to the grid (before row compaction).
    private var returningSpellingSlotIndices: Set<Int> = []
    /// Tiles mid-return; blocks duplicate taps and lost grid restoration.
    private var tilesReturningToGrid: Set<ObjectIdentifier> = []
    private var pendingReturnRemovalIndices: Set<Int> = []

    private func logAnimation(_ message: String) {
        print("[KanaSpelling] \(message)")
    }

    init(
        word: KanaSpellingWord,
        wordIndex: Int = 0,
        totalSteps: Int = KanaSpellingWordBank.words.count,
        promptStyle: KanaSpellingPromptStyle = .romaji,
        script: KanaScript = .hiragana
    ) {
        self.promptStyle = promptStyle
        self.script = script
        currentWordIndex = wordIndex
        self.totalSteps = max(totalSteps, 1)
        challenge = (word.hiragana, word.romaji, word.meaning)
        targetSyllables = HiraganaRomaji.syllables(in: challenge.hiragana, script: script)
        let layout = Self.gridLayout(forSyllableCount: targetSyllables.count)
        gridRows = layout.rows
        gridCellCount = layout.cellCount
        gridPlaceholders = Array(repeating: nil, count: layout.cellCount)
        spellingSlotTiles = Array(repeating: nil, count: targetSyllables.count)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStepIndex(_ stepIndex: Int, totalSteps: Int) {
        currentWordIndex = stepIndex
        self.totalSteps = totalSteps
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        targetWordContainer.bringSubviewToFront(replayControl)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ExperimentFeedbackSound.prepareClick()
        buildUI()
        configureSpellingRowGestures()
        populateGrid()
        syncSpellingSlotVisibility()
        updateCheckButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard promptStyle == .audio, !didAutoPlayChallenge else { return }
        didAutoPlayChallenge = true
        playChallengePronunciation()
    }

    // MARK: UI

    private func buildUI() {
        switch promptStyle {
        case .romaji:
            configureInstruction("Tap the kana to build the word")
        case .audio:
            configureInstruction("Listen, then spell the word")
        }
        instructionLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        meaningLabel.font = .preferredFont(forTextStyle: .footnote)
        meaningLabel.textAlignment = .center
        meaningLabel.adjustsFontForContentSizeCategory = true
        meaningLabel.textColor = .secondaryLabel
        meaningLabel.numberOfLines = 0
        meaningLabel.translatesAutoresizingMaskIntoConstraints = false
        meaningLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        applyMeaningLabel()

        targetLabel.font = .systemFont(ofSize: 34, weight: .bold)
        targetLabel.textAlignment = .center
        targetLabel.adjustsFontForContentSizeCategory = true
        targetLabel.textColor = .label
        targetLabel.numberOfLines = 0
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        targetLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        applyPromptStyleToTarget()

        promptTextStack.axis = .vertical
        promptTextStack.alignment = .center
        promptTextStack.spacing = 2
        promptTextStack.translatesAutoresizingMaskIntoConstraints = false
        promptTextStack.addArrangedSubview(targetLabel)
        promptTextStack.addArrangedSubview(meaningLabel)
        promptTextStack.setContentCompressionResistancePriority(.required, for: .vertical)

        replayControl.addTarget(self, action: #selector(replayPronunciationTapped))
        applyReplayControlVisibilityForPromptStyle()

        targetWordContainer.translatesAutoresizingMaskIntoConstraints = false
        targetWordContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        targetWordContainer.setContentHuggingPriority(.defaultHigh, for: .vertical)
        if promptStyle == .audio {
            let rowStack = UIStackView(arrangedSubviews: [promptTextStack, replayControl])
            rowStack.axis = .horizontal
            rowStack.alignment = .center
            rowStack.spacing = Self.replayButtonSpacing
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            targetWordContainer.addSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.centerXAnchor.constraint(equalTo: targetWordContainer.centerXAnchor),
                rowStack.topAnchor.constraint(equalTo: targetWordContainer.topAnchor),
                rowStack.bottomAnchor.constraint(equalTo: targetWordContainer.bottomAnchor),
                rowStack.leadingAnchor.constraint(greaterThanOrEqualTo: targetWordContainer.leadingAnchor),
                rowStack.trailingAnchor.constraint(lessThanOrEqualTo: targetWordContainer.trailingAnchor),
            ])
        } else {
            targetWordContainer.addSubview(promptTextStack)
            targetWordContainer.addSubview(replayControl)
        }

        setCTAMode(.check)

        spellingLine.backgroundColor = ExperimentPalette.prominentSeparator
        spellingLine.translatesAutoresizingMaskIntoConstraints = false

        spellingStack.axis = .horizontal
        spellingStack.alignment = .center
        spellingStack.distribution = .fill
        spellingStack.spacing = Self.spellingSlotSpacing

        for _ in targetSyllables {
            let slot = makeSlotView()
            slot.isHidden = true
            spellingStack.addArrangedSubview(slot)
            spellingSlots.append(slot)
        }

        spellingRowContainer.translatesAutoresizingMaskIntoConstraints = false
        spellingStack.translatesAutoresizingMaskIntoConstraints = false
        spellingRowContainer.addSubview(spellingStack)

        spellingRowWrapper.translatesAutoresizingMaskIntoConstraints = false
        spellingRowWrapper.isUserInteractionEnabled = true
        spellingRowContainer.isUserInteractionEnabled = true
        spellingStack.isUserInteractionEnabled = true
        spellingRowWrapper.addSubview(spellingRowContainer)
        NSLayoutConstraint.activate([
            spellingRowWrapper.heightAnchor.constraint(equalToConstant: Self.tileHeight),
            spellingRowWrapper.widthAnchor.constraint(equalTo: spellingRowContainer.widthAnchor),

            spellingRowContainer.centerXAnchor.constraint(equalTo: spellingRowWrapper.centerXAnchor),
            spellingRowContainer.topAnchor.constraint(equalTo: spellingRowWrapper.topAnchor),
            spellingRowContainer.bottomAnchor.constraint(equalTo: spellingRowWrapper.bottomAnchor),
            spellingRowContainer.heightAnchor.constraint(equalToConstant: Self.tileHeight),
            spellingRowContainer.widthAnchor.constraint(equalTo: spellingStack.widthAnchor),

            spellingStack.leadingAnchor.constraint(equalTo: spellingRowContainer.leadingAnchor),
            spellingStack.topAnchor.constraint(equalTo: spellingRowContainer.topAnchor),
            spellingStack.bottomAnchor.constraint(equalTo: spellingRowContainer.bottomAnchor),
            spellingStack.trailingAnchor.constraint(equalTo: spellingRowContainer.trailingAnchor),
        ])
        spellingRowWrapper.setContentHuggingPriority(.required, for: .vertical)
        spellingRowWrapper.setContentCompressionResistancePriority(.required, for: .vertical)

        spellingLineWrapper.translatesAutoresizingMaskIntoConstraints = false
        spellingLineWrapper.addSubview(spellingLine)
        NSLayoutConstraint.activate([
            spellingLine.topAnchor.constraint(equalTo: spellingLineWrapper.topAnchor),
            spellingLine.bottomAnchor.constraint(equalTo: spellingLineWrapper.bottomAnchor),
            spellingLine.heightAnchor.constraint(equalToConstant: 1),
        ])

        gridStack.axis = .vertical
        gridStack.alignment = .center
        gridStack.spacing = Self.gridSpacing
        gridStack.distribution = .fill

        buildGridRows()

        targetWordContainer.setContentCompressionResistancePriority(.required, for: .vertical)

        let spellingAreaStack = UIStackView(arrangedSubviews: [spellingRowWrapper, spellingLineWrapper])
        spellingAreaStack.axis = .vertical
        spellingAreaStack.alignment = .center
        spellingAreaStack.spacing = Self.spellingRowToLineSpacing
        spellingAreaStack.translatesAutoresizingMaskIntoConstraints = false

        let wordToSpellingSpacing = promptStyle == .audio ? 18 : Self.wordToSpellingSpacing
        let contentStack = makeLessonContentStack(
            belowInstruction: [targetWordContainer, spellingAreaStack, gridStack],
            afterInstructionSpacing: promptStyle == .audio ? 10 : 12
        )
        contentStack.alignment = .center
        contentStack.distribution = .fill
        contentStack.setCustomSpacing(wordToSpellingSpacing, after: targetWordContainer)
        contentStack.setCustomSpacing(28, after: spellingAreaStack)
        gridStack.setContentHuggingPriority(.required, for: .vertical)
        gridStack.setContentCompressionResistancePriority(.required, for: .vertical)

        installLessonContent(contentStack)

        NSLayoutConstraint.activate([
            targetWordContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),

            spellingLine.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Self.spellingLineHorizontalPadding
            ),
            spellingLine.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Self.spellingLineHorizontalPadding
            ),
        ])
        installPromptStyleConstraints()
    }

    private func applyMeaningLabel() {
        guard !challenge.meaning.isEmpty else {
            meaningLabel.text = nil
            meaningLabel.isHidden = true
            return
        }
        meaningLabel.text = "(\(challenge.meaning))"
        meaningLabel.isHidden = false
    }

    private func applyPromptStyleToTarget() {
        switch promptStyle {
        case .romaji:
            targetLabel.text = challenge.romaji
            targetLabel.isHidden = false
            targetLabel.alpha = 1
        case .audio:
            targetLabel.text = nil
            targetLabel.isHidden = true
            targetLabel.alpha = 1
            targetLabel.transform = .identity
        }
    }

    private func installPromptStyleConstraints() {
        switch promptStyle {
        case .romaji:
            NSLayoutConstraint.activate([
                promptTextStack.topAnchor.constraint(equalTo: targetWordContainer.topAnchor),
                promptTextStack.bottomAnchor.constraint(equalTo: targetWordContainer.bottomAnchor),
                promptTextStack.centerXAnchor.constraint(equalTo: targetWordContainer.centerXAnchor),
                promptTextStack.leadingAnchor.constraint(greaterThanOrEqualTo: targetWordContainer.leadingAnchor),
                promptTextStack.trailingAnchor.constraint(lessThanOrEqualTo: targetWordContainer.trailingAnchor),

                replayControl.leadingAnchor.constraint(
                    equalTo: targetLabel.trailingAnchor,
                    constant: Self.replayButtonSpacing
                ),
                replayControl.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            ])
        case .audio:
            break
        }
    }

    private func revealAnswerAfterSuccess() {
        guard promptStyle == .audio else { return }

        targetLabel.text = challenge.romaji
        targetLabel.isHidden = false
        targetLabel.alpha = 0
        targetLabel.transform = CGAffineTransform(translationX: 10, y: 0)
            .scaledBy(x: 0.94, y: 0.94)

        UIView.animate(
            withDuration: 0.34,
            delay: 0.06,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.55,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.targetLabel.alpha = 1
            self.targetLabel.transform = .identity
            self.targetWordContainer.layoutIfNeeded()
        }
    }

    private func applyReplayControlVisibilityForPromptStyle() {
        switch promptStyle {
        case .romaji:
            replayControl.alpha = 0
            replayControl.button.isUserInteractionEnabled = false
            replayControl.isAccessibilityElement = false
        case .audio:
            replayControl.alpha = 1
            replayControl.button.isUserInteractionEnabled = true
            replayControl.isAccessibilityElement = true
        }
    }

    private func spellingRowFilledCount() -> Int {
        spellingSlotTiles.compactMap { $0 }.count
    }

    private func canCheckSpelling() -> Bool {
        spellingRowFilledCount() >= targetSyllables.count
    }

    private func updateCheckButtonState() {
        switch ctaMode {
        case .check:
            primaryButton.isEnabled = canCheckSpelling() && !hasSucceeded
        case .next:
            primaryButton.isEnabled = true
        }
    }

    private func setCTAMode(_ mode: CTAMode) {
        ctaMode = mode
        switch mode {
        case .check:
            configureCTA(
                .custom(title: "Check", style: .blue, accessibilityLabel: "Check spelling"),
                target: self,
                action: #selector(primaryButtonTapped)
            )
        case .next:
            let isLast = currentWordIndex >= totalSteps - 1
            configureCTA(
                .custom(
                    title: isLast ? "Done" : "Next",
                    style: .yellow,
                    accessibilityLabel: isLast ? "Finish" : "Next word"
                ),
                target: self,
                action: #selector(primaryButtonTapped)
            )
        }
        updateCheckButtonState()
    }

    private func setReplayButtonVisible(_ visible: Bool, animated: Bool = true) {
        guard promptStyle != .audio else { return }

        let apply = {
            self.replayControl.alpha = visible ? 1 : 0
            self.replayControl.button.isUserInteractionEnabled = visible
            self.replayControl.isAccessibilityElement = visible
        }
        guard animated else {
            apply()
            return
        }
        if visible {
            replayControl.alpha = 0
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            apply()
        }
    }

    @objc private func primaryButtonTapped() {
        switch ctaMode {
        case .check:
            checkAnswer()
        case .next:
            advanceToNextWord()
        }
    }

    private func checkAnswer() {
        guard !hasSucceeded, canCheckSpelling() else { return }

        let filled = spellingSlotTiles.compactMap { $0 }
        let built = filled.map(\.kana).joined()
        guard built == challenge.hiragana else {
            onStepResult?(targetSyllables, false)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
            playIncorrectShake()
            return
        }

        hasSucceeded = true
        onStepResult?(targetSyllables, true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        successCascadeGeneration += 1
        let generation = successCascadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + KanaSpellingMotion.successCheckDelay) { [weak self] in
            guard let self, generation == self.successCascadeGeneration, self.hasSucceeded else { return }
            let successSound = ExperimentFeedbackSound.prepareSuccess(
                for: .kanaSpelling,
                spellingSyllableCount: filled.count
            )
            self.playSuccessCascade(tiles: filled, successSound: successSound) { [weak self] in
                guard let self else { return }
                if self.promptStyle == .audio {
                    self.revealAnswerAfterSuccess()
                } else {
                    self.setReplayButtonVisible(true)
                }
                self.setCTAMode(.next)
                self.playChallengePronunciation()
            }
        }
    }

    private func advanceToNextWord() {
        guard hasSucceeded else { return }
        progressiveContainerCoordinator?.advanceToNextStep(from: self)
    }

    private func loadChallenge(hiragana: String, romaji: String) {
        pronunciationPlayer.stop()
        returnLayoutWorkItem?.cancel()
        returnLayoutWorkItem = nil
        successCascadeGeneration += 1
        hasSucceeded = false
        setReplayButtonVisible(false, animated: false)
        setCTAMode(.check)
        dragTile = nil
        dragFlyer?.removeFromSuperview()
        dragFlyer = nil
        dragSlotPlaceholder?.removeFromSuperview()
        dragSlotPlaceholder = nil
        dragCurrentIndex = nil
        tilesReturningToGrid.removeAll()
        returningSpellingSlotIndices.removeAll()
        pendingReturnRemovalIndices.removeAll()
        for tile in spellingSlotTiles.compactMap({ $0 }) {
            tile.removeFromSuperview()
        }

        for row in gridRowStacks {
            for subview in row.arrangedSubviews {
                row.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
        }
        challenge = (hiragana, romaji, challenge.meaning)
        applyMeaningLabel()
        applyPromptStyleToTarget()
        let newSyllables = HiraganaRomaji.syllables(in: hiragana, script: script)

        let newLayout = Self.gridLayout(forSyllableCount: newSyllables.count)
        if newLayout.cellCount != gridCellCount {
            gridCellCount = newLayout.cellCount
            gridRows = newLayout.rows
            rebuildGridRows()
        }
        gridPlaceholders = Array(repeating: nil, count: gridCellCount)

        if newSyllables.count != targetSyllables.count {
            rebuildSpellingSlots(syllableCount: newSyllables.count)
        } else {
            spellingSlotTiles = Array(repeating: nil, count: newSyllables.count)
            for slot in spellingSlots {
                slot.subviews.forEach { $0.removeFromSuperview() }
            }
        }
        targetSyllables = newSyllables

        syncSpellingSlotVisibility()
        populateGrid()
        updateCheckButtonState()
    }

    private func rebuildSpellingSlots(syllableCount: Int) {
        spellingStack.arrangedSubviews.forEach { view in
            spellingStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        spellingSlots.removeAll()
        spellingSlotTiles = Array(repeating: nil, count: syllableCount)
        for _ in 0 ..< syllableCount {
            let slot = makeSlotView()
            slot.isHidden = true
            spellingStack.addArrangedSubview(slot)
            spellingSlots.append(slot)
        }
    }

    @objc private func replayPronunciationTapped() {
        playChallengePronunciation()
    }

    private func playChallengePronunciation() {
        if let assetName = KanaSpellingWordBank.successAudioByHiragana[challenge.hiragana] {
            pronunciationPlayer.play(assetNamed: assetName)
        } else {
            pronunciationPlayer.play(kana: challenge.hiragana, languageIdentifier: "ja-JP")
        }
    }

    private func playIncorrectShake() {
        let views: [UIView] = [spellingRowContainer, gridStack]
        let displacement = KanaSpellingMotion.incorrectShakeDisplacement
        let key = "kanaSpelling.shake"

        for view in views {
            view.layer.removeAnimation(forKey: key)
            view.transform = .identity

            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.duration = KanaSpellingMotion.incorrectShakeDuration
            animation.values = [
                0,
                -displacement,
                displacement,
                -displacement * 0.72,
                displacement * 0.72,
                -displacement * 0.4,
                displacement * 0.4,
                0,
            ]
            view.layer.add(animation, forKey: key)
        }
    }

    private func makeSlotView() -> UIView {
        let slot = UIView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: Self.tileWidth),
            slot.heightAnchor.constraint(equalToConstant: Self.tileHeight),
        ])
        return slot
    }

    private func makeGridPlaceholder() -> UIView {
        let gap = UIView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            gap.widthAnchor.constraint(equalToConstant: Self.tileWidth),
            gap.heightAnchor.constraint(equalToConstant: Self.tileHeight),
        ])
        return gap
    }

    // MARK: Grid

    private static func gridLayout(forSyllableCount count: Int) -> (rows: Int, cellCount: Int) {
        let bankSize = KanaSpellingDifficulty.forSyllableCount(count).characterBankSize
        return (bankSize / gridColumns, bankSize)
    }

    private func buildGridRows() {
        for _ in 0 ..< gridRows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.distribution = .equalSpacing
            row.spacing = Self.gridSpacing
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: Self.tileHeight).isActive = true
            gridRowStacks.append(row)
            gridStack.addArrangedSubview(row)
        }
    }

    private func rebuildGridRows() {
        for row in gridRowStacks {
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        gridRowStacks.removeAll()
        buildGridRows()
    }

    private func populateGrid() {
        var pool = targetSyllables
        let neededDistractors = gridCellCount - pool.count
        let distractorCandidates = HiraganaRomaji.allGlyphs(script: script).filter { !targetSyllables.contains($0) }
        let shuffledDistractors = distractorCandidates.shuffled()
        for i in 0 ..< neededDistractors {
            pool.append(shuffledDistractors[i % shuffledDistractors.count])
        }
        pool.shuffle()

        for (index, kana) in pool.enumerated() {
            let tile = KanaSpellingTile(kana: kana)
            tile.homeGridIndex = index
            wireGridTap(tile)

            let row = index / Self.gridColumns
            let column = index % Self.gridColumns
            gridRowStacks[row].insertArrangedSubview(tile, at: column)
        }
    }

    private func rowAndColumn(forGridIndex index: Int) -> (row: Int, column: Int) {
        (index / Self.gridColumns, index % Self.gridColumns)
    }

    private func removeTileFromGrid(_ tile: KanaSpellingTile) {
        guard let index = tile.homeGridIndex else { return }
        let (row, column) = rowAndColumn(forGridIndex: index)
        let rowStack = gridRowStacks[row]

        rowStack.removeArrangedSubview(tile)
        tile.removeFromSuperview()

        let placeholder = makeGridPlaceholder()
        rowStack.insertArrangedSubview(placeholder, at: column)
        gridPlaceholders[index] = placeholder
    }

    private func insertTileInGrid(_ tile: KanaSpellingTile) {
        guard let index = tile.homeGridIndex else { return }
        tile.removeFromSuperview()
        let (row, column) = rowAndColumn(forGridIndex: index)
        let rowStack = gridRowStacks[row]

        if let placeholder = gridPlaceholders[index] {
            rowStack.removeArrangedSubview(placeholder)
            placeholder.removeFromSuperview()
            gridPlaceholders[index] = nil
        }

        rowStack.insertArrangedSubview(tile, at: column)
        wireGridTap(tile)
    }

    private func wireGridTap(_ tile: KanaSpellingTile) {
        tile.removeAction(identifiedBy: .kanaGridTap, for: .touchUpInside)
        tile.removeAction(identifiedBy: .kanaSpellingTap, for: .touchUpInside)
        tile.isUserInteractionEnabled = true
        tile.addAction(UIAction(identifier: .kanaGridTap) { [weak self, weak tile] _ in
            guard let self, let tile else { return }
            self.gridTileTapped(tile)
        }, for: .touchUpInside)
    }

    private func wireSpellingTap(_ tile: KanaSpellingTile) {
        tile.removeAction(identifiedBy: .kanaGridTap, for: .touchUpInside)
        tile.removeAction(identifiedBy: .kanaSpellingTap, for: .touchUpInside)
        tile.isUserInteractionEnabled = true
        tile.addTarget(self, action: #selector(spellingTileTouchUpInside(_:)), for: .touchUpInside)
    }

    @objc
    private func spellingTileTouchUpInside(_ sender: UIControl) {
        guard let tile = sender as? KanaSpellingTile else { return }
        spellingTileTapped(tile)
    }

    private func configureSpellingRowGestures() {
        // TEMP: long-press reorder disabled while testing tap-to-return.
        // spellingReorderRecognizer.addTarget(self, action: #selector(handleSpellingTileDrag(_:)))
        // spellingReorderRecognizer.minimumPressDuration = KanaSpellingMotion.reorderPressDuration
        // spellingReorderRecognizer.allowableMovement = KanaSpellingMotion.reorderAllowableMovement
        // spellingReorderRecognizer.cancelsTouchesInView = false
        // spellingReorderRecognizer.delaysTouchesEnded = false
        // spellingReorderRecognizer.delegate = self
        // spellingRowWrapper.addGestureRecognizer(spellingReorderRecognizer)
    }

    private func spellingTile(at point: CGPoint, in coordinateView: UIView) -> KanaSpellingTile? {
        for (index, tile) in spellingSlotTiles.enumerated() {
            guard let tile, !tile.isHidden else { continue }
            let slot = spellingSlots[index]
            guard !slot.isHidden else { continue }

            let tileFrame = tile.convert(tile.bounds, to: coordinateView)
            if tileFrame.contains(point) {
                return tile
            }

            let slotFrame = slot.convert(slot.bounds, to: coordinateView)
            if slotFrame.contains(point) {
                return tile
            }
        }
        return nil
    }

    private func embed(tile: KanaSpellingTile, in slot: UIView) {
        slot.subviews.forEach { $0.removeFromSuperview() }
        slot.addSubview(tile)
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            tile.topAnchor.constraint(equalTo: slot.topAnchor),
            tile.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
        ])
    }

    // MARK: Spelling row layout

    private func spellingGroupWidth(forCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * Self.tileWidth + CGFloat(count - 1) * Self.spellingSlotSpacing
    }

    private func spellingRowContainerWidth() -> CGFloat {
        let width = spellingRowContainer.bounds.width
        if width > 0 { return width }
        return max(view.bounds.width - 48, 0)
    }

    /// Target frame for a spelling slot when `count` tiles are visible (matches centered stack layout).
    private func spellingSlotFrame(at index: Int, occupiedCount count: Int, relativeTo coordinateView: UIView) -> CGRect {
        let groupWidth = spellingGroupWidth(forCount: count)
        let leading = (spellingRowContainerWidth() - groupWidth) / 2
        let x = leading + CGFloat(index) * (Self.tileWidth + Self.spellingSlotSpacing)
        let rect = CGRect(x: x, y: 0, width: Self.tileWidth, height: Self.tileHeight)
        return spellingRowContainer.convert(rect, to: coordinateView)
    }

    private func syncSpellingSlotVisibility() {
        let lastOccupied = spellingSlotTiles.enumerated().last(where: { $0.element != nil })?.offset ?? -1
        let lastReturning = returningSpellingSlotIndices.max() ?? -1
        let lastVisible = max(lastOccupied, lastReturning)
        for (index, slot) in spellingSlots.enumerated() {
            if spellingSlotTiles[index] != nil || returningSpellingSlotIndices.contains(index) {
                slot.isHidden = false
            } else {
                slot.isHidden = index > lastVisible
            }
        }
        updateCheckButtonState()
    }

    private func applySpellingRowLayoutWithoutAnimation() {
        syncSpellingSlotVisibility()
        UIView.performWithoutAnimation {
            spellingRowContainer.layoutIfNeeded()
        }
    }

    /// Slides embedded spelling tiles when the centered group width changes (no full-view layout animation).
    private func animateSpellingTilesShift(
        slideFromFrames: [(tile: KanaSpellingTile, frame: CGRect)],
        occupiedCount: Int,
        delay: TimeInterval = 0,
        completion: (() -> Void)? = nil
    ) {
        guard let window = view.window else {
            completion?()
            return
        }

        var moves: [(KanaSpellingTile, UIView, CGRect, CGRect)] = []
        for (tile, from) in slideFromFrames {
            guard let index = spellingSlotTiles.firstIndex(where: { $0 === tile }) else { continue }
            let slot = spellingSlots[index]
            let to = spellingSlotFrame(at: index, occupiedCount: occupiedCount, relativeTo: window)
            if hypot(from.midX - to.midX, from.midY - to.midY) > 0.5 {
                moves.append((tile, slot, from, to))
            }
        }

        guard !moves.isEmpty else {
            logAnimation("slideShift none (occupied=\(occupiedCount))")
            completion?()
            return
        }

        logAnimation("slideShift moves=\(moves.count) occupied=\(occupiedCount) delay=\(String(format: "%.2f", delay))")

        let group = DispatchGroup()
        for (tile, slot, from, to) in moves {
            group.enter()
            logAnimation(
                "slide \(tile.kana) from=\(Int(from.midX)),\(Int(from.midY)) to=\(Int(to.midX)),\(Int(to.midY))"
            )
            animateTileSlide(tile: tile, in: slot, from: from, to: to, delay: delay) {
                group.leave()
            }
        }
        group.notify(queue: .main) { completion?() }
    }

    // MARK: Interaction

    private func isTileInGrid(_ tile: KanaSpellingTile) -> Bool {
        guard let index = tile.homeGridIndex else { return false }
        return gridPlaceholders[index] == nil && !spellingSlotTiles.contains(where: { $0 === tile })
    }

    private func nextSpellingSlotIndex() -> Int? {
        spellingSlotTiles.firstIndex(where: { $0 == nil })
    }

    private func spellingIsCorrectAndComplete() -> Bool {
        let filled = spellingSlotTiles.compactMap { $0 }
        guard filled.count == targetSyllables.count else { return false }
        return filled.map(\.kana).joined() == challenge.hiragana
    }

    private func playTileTapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func gridTileTapped(_ tile: KanaSpellingTile) {
        guard !hasSucceeded else { return }
        guard isTileInGrid(tile), let slotIndex = nextSpellingSlotIndex() else { return }

        tile.cancelPressFeedback()
        playTileTapHaptic()
        pronunciationPlayer.play(kana: tile.kana)
        logAnimation("tap grid \(tile.kana) -> slot \(slotIndex)")

        let slot = spellingSlots[slotIndex]
        let previousCount = spellingSlotTiles.compactMap { $0 }.count
        let existingTiles = spellingSlotTiles[0 ..< previousCount].compactMap { $0 }

        spellingSlotTiles[slotIndex] = tile

        animateSpellingRelayout(
            tiles: existingTiles,
            duration: KanaSpellingMotion.slideDuration,
            updates: { [weak self] in
                self?.syncSpellingSlotVisibility()
            }
        )

        wireSpellingTap(tile)
        animateFromGrid(tile: tile, to: slot, landingFrame: nil, completion: {})
    }

    private func spellingTileTapped(_ tile: KanaSpellingTile) {
        guard dragTile == nil else { return }
        let tileID = ObjectIdentifier(tile)
        guard !tilesReturningToGrid.contains(tileID) else { return }
        guard let spellingIndex = spellingSlotTiles.firstIndex(where: { $0 === tile }) else { return }
        guard let homeIndex = tile.homeGridIndex, let window = view.window else { return }

        tile.cancelPressFeedback()
        playTileTapHaptic()

        hasSucceeded = false
        successCascadeGeneration += 1
        if promptStyle == .audio {
            applyPromptStyleToTarget()
        }
        setReplayButtonVisible(false, animated: false)
        setCTAMode(.check)
        let previousCount = spellingSlotTiles.compactMap { $0 }.count
        let newCount = previousCount - 1

        tilesReturningToGrid.insert(tileID)
        returningSpellingSlotIndices.insert(spellingIndex)
        spellingSlotTiles[spellingIndex] = nil
        tile.setHighlight(.normal)
        syncSpellingSlotVisibility()

        // Capture while the vacated slot is still reserved in the row.
        view.layoutIfNeeded()
        let startFrame = tile.convert(tile.bounds, to: window)

        let placeholder = prepareGridPlaceholder(at: homeIndex)
        view.layoutIfNeeded()
        let landingFrame = tileFrame(in: placeholder, relativeTo: window)
        logAnimation(
            "tap spelling \(tile.kana) slot=\(spellingIndex) -> grid=\(homeIndex) from=\(Int(startFrame.midX)),\(Int(startFrame.midY)) to=\(Int(landingFrame.midX)),\(Int(landingFrame.midY))"
        )

        if newCount > 0 {
            scheduleSpellingReturnLayout(removingAt: spellingIndex)
        }

        let group = DispatchGroup()
        group.enter()
        animateReturnToGrid(
            tile: tile,
            spellingSlotIndex: spellingIndex,
            landingFrame: landingFrame,
            startFrame: startFrame
        ) { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            self.tilesReturningToGrid.remove(tileID)
            self.returningSpellingSlotIndices.remove(spellingIndex)
            if newCount == 0 {
                self.applySpellingRowLayoutWithoutAnimation()
            }
        }

    }

    // TEMP: long-press reorder disabled while testing tap-to-return.
    /*
    @objc
    private func handleSpellingTileDrag(_ recognizer: KanaSpellingReorderGestureRecognizer) {
        guard !hasSucceeded else { return }
        guard let window = view.window else { return }

        let pointer = recognizer.location(in: window)
        switch recognizer.state {
        case .began:
            guard dragTile == nil,
                  let tile = spellingTile(at: pointer, in: window)
            else { return }
            beginSpellingDrag(tile: tile, pointer: pointer, in: window)
        case .changed:
            updateSpellingDrag(pointer: pointer, in: window)
        case .ended:
            endSpellingDrag(cancelled: false)
        case .cancelled, .failed:
            if dragTile != nil {
                endSpellingDrag(cancelled: true)
            } else if let tile = spellingTile(at: pointer, in: window) {
                spellingTileTapped(tile)
            }
        default:
            break
        }
    }
    */

    private func beginSpellingDrag(tile: KanaSpellingTile, pointer: CGPoint, in window: UIWindow) {
        compactSpellingSlotsIfNeeded()

        guard let index = spellingSlotTiles.firstIndex(where: { $0 === tile }) else { return }
        let startFrame = tile.convert(tile.bounds, to: window)
        guard let flyer = makeFlyer(from: tile, afterScreenUpdates: false) else { return }

        dragTile = tile
        dragFlyer = flyer
        dragCurrentIndex = index
        dragTouchOffset = CGPoint(x: pointer.x - startFrame.midX, y: pointer.y - startFrame.midY)

        flyer.frame = startFrame
        flyer.layer.zPosition = 1000
        flyer.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        window.addSubview(flyer)
        tile.isHidden = true

        let slot = spellingSlots[index]
        let placeholder = UIView()
        placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: Self.tileWidth),
            placeholder.heightAnchor.constraint(equalToConstant: Self.tileHeight),
        ])
        dragSlotPlaceholder = placeholder
        // Detach from slot so re-embed passes don't cancel the row-level gesture.
        tile.removeFromSuperview()
    }

    private func updateSpellingDrag(pointer: CGPoint, in window: UIWindow) {
        guard let tile = dragTile,
              let flyer = dragFlyer,
              let currentIndex = dragCurrentIndex
        else { return }

        flyer.center = CGPoint(x: pointer.x - dragTouchOffset.x, y: pointer.y - dragTouchOffset.y)
        let occupiedCount = spellingSlotTiles.compactMap { $0 }.count
        guard occupiedCount > 1 else { return }
        let targetIndex = nearestSpellingSlotIndex(forX: flyer.center.x, occupiedCount: occupiedCount, in: window)
        guard targetIndex != currentIndex else { return }

        let movingTiles = (0 ..< occupiedCount)
            .compactMap { spellingSlotTiles[$0] }
            .filter { $0 !== tile }

        animateSpellingRelayout(tiles: movingTiles, duration: KanaSpellingMotion.snapDuration) {
            moveSpellingTile(from: currentIndex, to: targetIndex, occupiedCount: occupiedCount)
            for index in 0 ..< occupiedCount {
                guard let existing = spellingSlotTiles[index], existing !== tile else { continue }
                embed(tile: existing, in: spellingSlots[index])
                wireSpellingTap(existing)
            }
            applySpellingRowLayoutWithoutAnimation()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dragCurrentIndex = targetIndex
    }

    private func endSpellingDrag(cancelled: Bool) {
        defer {
            dragTile = nil
            dragFlyer = nil
            dragCurrentIndex = nil
            dragTouchOffset = .zero
        }

        guard let tile = dragTile else { return }
        dragSlotPlaceholder?.removeFromSuperview()
        dragSlotPlaceholder = nil
        dragFlyer?.removeFromSuperview()
        tile.isHidden = false
        tile.transform = .identity
        tile.setHighlight(.selected)

        guard let finalIndex = spellingSlotTiles.firstIndex(where: { $0 === tile }) else { return }
        let destination = spellingSlots[finalIndex]
        embed(tile: tile, in: destination)
        wireSpellingTap(tile)
        runArrivalBounce(on: tile) {}
    }

    private func compactSpellingSlotsIfNeeded() {
        let lastOccupied = spellingSlotTiles.enumerated().last(where: { $0.element != nil })?.offset ?? -1
        guard lastOccupied >= 0 else { return }
        let hasGap = spellingSlotTiles[0 ... lastOccupied].contains(where: { $0 == nil })
        guard hasGap else { return }

        let remaining = spellingSlotTiles.compactMap { $0 }
        var compacted = Array(repeating: nil as KanaSpellingTile?, count: targetSyllables.count)
        for (index, tile) in remaining.enumerated() {
            compacted[index] = tile
        }
        spellingSlotTiles = compacted
        syncSpellingSlotVisibility()
        applySpellingRowLayoutWithoutAnimation()
        for tile in remaining {
            wireSpellingTap(tile)
        }
    }

    private func moveSpellingTile(from sourceIndex: Int, to destinationIndex: Int, occupiedCount: Int) {
        guard sourceIndex != destinationIndex else { return }
        var occupied = spellingSlotTiles[0 ..< occupiedCount].compactMap { $0 }
        guard sourceIndex < occupied.count, destinationIndex < occupied.count else { return }
        let moved = occupied.remove(at: sourceIndex)
        occupied.insert(moved, at: destinationIndex)

        var rebuilt = Array(repeating: nil as KanaSpellingTile?, count: targetSyllables.count)
        for (index, tile) in occupied.enumerated() {
            rebuilt[index] = tile
        }
        spellingSlotTiles = rebuilt
        syncSpellingSlotVisibility()
    }

    private func nearestSpellingSlotIndex(forX x: CGFloat, occupiedCount: Int, in window: UIWindow) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0 ..< occupiedCount {
            let frame = spellingSlotFrame(at: index, occupiedCount: occupiedCount, relativeTo: window)
            let distance = abs(frame.midX - x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private func scheduleSpellingReturnLayout(removingAt spellingIndex: Int) {
        pendingReturnRemovalIndices.insert(spellingIndex)
        returnLayoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyPendingReturnLayouts()
        }
        returnLayoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + KanaSpellingMotion.returnRowShiftDelay,
            execute: work
        )
    }

    /// Compact gaps and slide remaining tiles together after one or more tiles leave the spelling row.
    private func applyPendingReturnLayouts() {
        returnLayoutWorkItem = nil
        let removedIndices = pendingReturnRemovalIndices
        pendingReturnRemovalIndices.removeAll()
        returningSpellingSlotIndices.subtract(removedIndices)
        for index in removedIndices {
            spellingSlotTiles[index] = nil
        }
        syncSpellingSlotVisibility()
        let remaining = spellingSlotTiles.compactMap { $0 }
        let newCount = remaining.count
        logAnimation("apply return reflow remaining=\(newCount)")

        guard newCount > 0 else {
            applySpellingRowLayoutWithoutAnimation()
            return
        }

        var compacted = Array(repeating: nil as KanaSpellingTile?, count: targetSyllables.count)
        for (index, tile) in remaining.enumerated() {
            compacted[index] = tile
        }
        animateSpellingRelayout(
            tiles: remaining,
            duration: KanaSpellingMotion.returnSlideDuration
        ) { [weak self] in
            guard let self else { return }
            self.spellingSlotTiles = compacted
            self.syncSpellingSlotVisibility()
            for (index, tile) in remaining.enumerated() {
                self.embed(tile: tile, in: self.spellingSlots[index])
                self.wireSpellingTap(tile)
            }
            self.applySpellingRowLayoutWithoutAnimation()
        }
    }

    /// Re-layout existing spelling tiles with transform-based interpolation to avoid flyer jitter.
    private func animateSpellingRelayout(
        tiles: [KanaSpellingTile],
        duration: TimeInterval = KanaSpellingMotion.slideDuration,
        updates: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard let window = view.window else {
            updates()
            completion?()
            return
        }

        var before: [ObjectIdentifier: CGRect] = [:]
        for tile in tiles where tile.superview != nil && !tile.isHidden {
            before[ObjectIdentifier(tile)] = tile.convert(tile.bounds, to: window)
        }

        updates()
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
        }

        var movedTiles: [KanaSpellingTile] = []
        for tile in tiles where tile.superview != nil && !tile.isHidden {
            let id = ObjectIdentifier(tile)
            guard let from = before[id] else { continue }
            let to = tile.convert(tile.bounds, to: window)
            let dx = from.midX - to.midX
            let dy = from.midY - to.midY
            if hypot(dx, dy) > 0.5 {
                tile.layer.removeAllAnimations()
                tile.transform = CGAffineTransform(translationX: dx, y: dy)
                movedTiles.append(tile)
            }
        }

        guard !movedTiles.isEmpty else {
            completion?()
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            movedTiles.forEach { $0.transform = .identity }
        } completion: { _ in
            completion?()
        }
    }

    // MARK: Animation

    private func tileFrame(in container: UIView, relativeTo coordinateView: UIView) -> CGRect {
        view.layoutIfNeeded()
        let size = CGSize(width: Self.tileWidth, height: Self.tileHeight)
        let originInContainer = CGPoint(
            x: (container.bounds.width - size.width) / 2,
            y: (container.bounds.height - size.height) / 2
        )
        return CGRect(
            origin: container.convert(originInContainer, to: coordinateView),
            size: size
        )
    }

    private func prepareGridPlaceholder(at gridIndex: Int) -> UIView {
        let (row, column) = rowAndColumn(forGridIndex: gridIndex)
        let rowStack = gridRowStacks[row]
        if let existing = gridPlaceholders[gridIndex] {
            return existing
        }
        let placeholder = makeGridPlaceholder()
        rowStack.insertArrangedSubview(placeholder, at: column)
        gridPlaceholders[gridIndex] = placeholder
        return placeholder
    }

    private func makeFlyer(from tile: KanaSpellingTile, afterScreenUpdates: Bool) -> UIView? {
        guard let flyer = tile.snapshotView(afterScreenUpdates: afterScreenUpdates) else { return nil }
        flyer.layer.shadowPath = nil
        flyer.layer.shadowOpacity = tile.layer.shadowOpacity
        flyer.layer.shadowRadius = tile.layer.shadowRadius
        flyer.layer.shadowOffset = tile.layer.shadowOffset
        flyer.layer.shadowColor = tile.layer.shadowColor
        return flyer
    }

    /// Subtle settle-in on landing (no overshoot past 1.0).
    private func runArrivalBounce(on tile: UIView, completion: @escaping () -> Void) {
        tile.transform = CGAffineTransform(
            scaleX: KanaSpellingMotion.arrivalSettleScale,
            y: KanaSpellingMotion.arrivalSettleScale
        )
        UIView.animate(
            withDuration: KanaSpellingMotion.settleDuration,
            delay: 0,
            usingSpringWithDamping: KanaSpellingMotion.settleDamping,
            initialSpringVelocity: KanaSpellingMotion.settleVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            tile.transform = .identity
        } completion: { _ in
            completion()
        }
    }

    private func finishFlyer(
        _ flyer: UIView,
        tile: KanaSpellingTile,
        embedIn destination: UIView,
        landingHighlight: KanaSpellingTile.Highlight? = nil,
        bounce: Bool = true,
        completion: @escaping () -> Void
    ) {
        flyer.removeFromSuperview()
        tile.isHidden = false
        tile.alpha = 1
        tile.transform = .identity
        embed(tile: tile, in: destination)
        wireSpellingTap(tile)

        switch (landingHighlight, bounce) {
        case (.selected?, true):
            tile.animateLandingSelection(scaleBounce: false, completion: completion)
        case let (highlight?, false):
            tile.setHighlight(highlight, animated: true)
            completion()
        case (_, true):
            runArrivalBounce(on: tile, completion: completion)
        default:
            completion()
        }
    }

    private func finishFlyerInGrid(
        _ flyer: UIView,
        tile: KanaSpellingTile,
        completion: @escaping () -> Void
    ) {
        flyer.removeFromSuperview()
        tile.isHidden = false
        tile.alpha = 1
        tile.transform = .identity
        insertTileInGrid(tile)
        runArrivalBounce(on: tile, completion: completion)
    }

    private func animateFlight(
        flyer: UIView,
        from startFrame: CGRect,
        to endCenter: CGPoint,
        in window: UIWindow,
        completion: @escaping () -> Void
    ) {
        flyer.frame = startFrame
        window.addSubview(flyer)
        let animator = UIViewPropertyAnimator(
            duration: KanaSpellingMotion.flightDuration,
            timingParameters: KanaSpellingMotion.flightTiming
        )
        animator.addAnimations {
            flyer.center = endCenter
        }
        animator.addCompletion { position in
            guard position == .end else { return }
            completion()
        }
        animator.startAnimation()
    }

    /// Grid → spelling: cubic flight from grid cell, settle in slot (row shifts in parallel).
    private func animateFromGrid(
        tile: KanaSpellingTile,
        to slot: UIView,
        landingFrame: CGRect? = nil,
        completion: @escaping () -> Void
    ) {
        guard let window = view.window else {
            removeTileFromGrid(tile)
            embed(tile: tile, in: slot)
            completion()
            return
        }

        view.layoutIfNeeded()
        tile.cancelPressFeedback()
        let startFrame = tile.convert(tile.bounds, to: window)
        let endFrame = landingFrame ?? tileFrame(in: slot, relativeTo: window)

        guard let flyer = makeFlyer(from: tile, afterScreenUpdates: true) else {
            removeTileFromGrid(tile)
            embed(tile: tile, in: slot)
            completion()
            return
        }

        removeTileFromGrid(tile)
        tile.isHidden = true

        animateFlight(
            flyer: flyer,
            from: startFrame,
            to: CGPoint(x: endFrame.midX, y: endFrame.midY),
            in: window
        ) { [weak self] in
            guard let self else {
                completion()
                return
            }
            let skipLandingBounce = self.spellingIsCorrectAndComplete()
            self.finishFlyer(
                flyer,
                tile: tile,
                embedIn: slot,
                landingHighlight: .selected,
                bounce: !skipLandingBounce,
                completion: completion
            )
        }
    }

    /// Spelling → grid: reverse of `animateFromGrid` — cubic flight home, settle in grid cell.
    private func animateReturnToGrid(
        tile: KanaSpellingTile,
        spellingSlotIndex: Int,
        landingFrame: CGRect? = nil,
        startFrame: CGRect? = nil,
        completion: @escaping () -> Void
    ) {
        guard let homeIndex = tile.homeGridIndex, let window = view.window else {
            insertTileInGrid(tile)
            completion()
            return
        }

        let placeholder = prepareGridPlaceholder(at: homeIndex)
        let flightStart = startFrame ?? tile.convert(tile.bounds, to: window)
        let endFrame = landingFrame ?? tileFrame(in: placeholder, relativeTo: window)
        logAnimation(
            "return flight \(tile.kana) from=\(Int(flightStart.midX)),\(Int(flightStart.midY)) to=\(Int(endFrame.midX)),\(Int(endFrame.midY))"
        )

        guard let flyer = makeFlyer(from: tile, afterScreenUpdates: true) else {
            logAnimation("return flight fallback \(tile.kana) (no flyer)")
            spellingSlots[spellingSlotIndex].subviews.forEach { $0.removeFromSuperview() }
            insertTileInGrid(tile)
            completion()
            return
        }

        spellingSlots[spellingSlotIndex].subviews.forEach { $0.removeFromSuperview() }
        tile.isHidden = true

        animateFlight(
            flyer: flyer,
            from: flightStart,
            to: CGPoint(x: endFrame.midX, y: endFrame.midY),
            in: window
        ) { [weak self] in
            self?.finishFlyerInGrid(flyer, tile: tile, completion: completion)
        }
    }

    /// Smooth slide for spelling tiles already in the row (cubic ease, no stack layout animation).
    private func animateTileSlide(
        tile: KanaSpellingTile,
        in slot: UIView,
        from startFrame: CGRect,
        to endFrame: CGRect,
        delay: TimeInterval = 0,
        completion: @escaping () -> Void
    ) {
        guard let window = view.window else {
            embed(tile: tile, in: slot)
            wireSpellingTap(tile)
            completion()
            return
        }

        guard let flyer = makeFlyer(from: tile, afterScreenUpdates: true) else {
            embed(tile: tile, in: slot)
            wireSpellingTap(tile)
            completion()
            return
        }

        // Hide the real tile before slot relayout to avoid one-frame flashes.
        tile.isHidden = true
        slot.subviews.forEach { $0.removeFromSuperview() }
        flyer.frame = startFrame
        window.addSubview(flyer)

        let animator = UIViewPropertyAnimator(
            duration: KanaSpellingMotion.slideDuration,
            timingParameters: KanaSpellingMotion.flightTiming
        )
        animator.addAnimations {
            flyer.frame = endFrame
        }
        animator.addCompletion { [weak self] position in
            guard position == .end, let self else {
                completion()
                return
            }
            self.finishFlyer(flyer, tile: tile, embedIn: slot, bounce: false, completion: completion)
        }
        if delay > 0 {
            animator.startAnimation(afterDelay: delay)
        } else {
            animator.startAnimation()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // if gestureRecognizer === spellingReorderRecognizer { return !hasSucceeded }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }

    /// Staggered kana bounce + green highlight across spelling tiles, then `completion`.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    private func playSuccessCascade(
        tiles: [KanaSpellingTile],
        successSound: ExperimentFeedbackSound.PreparedSuccessSound,
        completion: @escaping () -> Void
    ) {
        let count = tiles.count
        guard count > 0 else {
            completion()
            return
        }

        successCascadeGeneration += 1
        let generation = successCascadeGeneration

        let stagger = KanaSpellingMotion.successCascadeStagger
        let chimeKeyTime = KanaSpellingMotion.successChimeKeyTime(forSyllableCount: count)
        let chimeLead = KanaSpellingMotion.successChimeLead(forSyllableCount: count)

        if chimeLead > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() - chimeLead) { [weak self] in
                guard let self, generation == self.successCascadeGeneration else { return }
                ExperimentFeedbackSound.playPreparedSuccessSound(successSound)
            }
        }

        for (index, tile) in tiles.enumerated() {
            let delay = Double(index) * stagger
            let isLast = index == count - 1
            let playsChimeOnBounce = index == 0 && chimeLead == 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, generation == self.successCascadeGeneration else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                tile.animateCorrectJump(
                    successSound: playsChimeOnBounce ? successSound : nil,
                    successChimeKeyTime: playsChimeOnBounce ? chimeKeyTime : nil
                ) {
                    guard generation == self.successCascadeGeneration else { return }
                    if isLast {
                        completion()
                    }
                }
            }
        }
    }
}

