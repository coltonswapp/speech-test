//
//  KanaSoundMatchExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: drag to match hiragana ↔ romaji sounds.
//

import UIKit

// MARK: - Typography

private enum MatchCardTypography {
    case hiragana
    case romaji

    var panelFontSize: CGFloat {
        switch self {
        case .hiragana: KanaSoundMatchStyle.kanaFontSize
        case .romaji: KanaSoundMatchStyle.romajiFontSize
        }
    }

    var dragFontSize: CGFloat {
        switch self {
        case .hiragana: KanaSoundMatchStyle.kanaFontSize
        case .romaji: KanaSoundMatchStyle.romajiFontSize
        }
    }

    var dragFontWeight: UIFont.Weight {
        switch self {
        case .hiragana: .bold
        case .romaji: .medium
        }
    }
}

// MARK: - Appearance

private enum KanaSoundMatchStyle {
    static let cardBackground = ExperimentPalette.cardSurface
    static let dragCardBackground = ExperimentPalette.dragCardSurface
    static let cardBorder = ExperimentPalette.cardBorder
    static let dropHighlightFill = ExperimentPalette.highlightFill
    static let dropHighlightBorder = ExperimentPalette.highlightBorder
    static let successFill = ExperimentPalette.successFill
    static let successBorder = ExperimentPalette.successBorder

    static let soundCardCornerRadius = ExperimentCardStroke.choiceCornerRadius
    static let kanaCardCornerRadius = ExperimentCardStroke.kanaDragCornerRadius
    static let kanaCardSide = KanaSoundMatchMetrics.kanaCardSide
    static let kanaFontSize: CGFloat = 30
    static let kanaSlotOffsetY: CGFloat = 12
    static let kanaSlotExtraOffsetY: CGFloat = 24
    static let romajiLabelShiftY: CGFloat = 24
    static let dropRotationRangeDegrees: CGFloat = 5
    static let placedCardScale = KanaSoundMatchMetrics.placedCardScale
    static let romajiFontSize: CGFloat = 24
    static let gridSpacing: CGFloat = 4
    static let gridToKanaSpacing: CGFloat = 8
    static let soundCardBorderWidth = ExperimentCardStroke.normalWidth
    static let dragCardBorderWidth = ExperimentCardStroke.normalWidth
    static let dropHighlightBorderWidth = ExperimentCardStroke.emphasisWidth
}

// MARK: - Sound card (drop target)

private final class SoundCardView: UIView, KanaSoundDropTarget {

    let choiceValue: String
    private let typography: MatchCardTypography

    private let soundPanel = UIView()
    private let choiceLabel = UILabel()
    private let kanaSlotView = UIView()
    private var keepsPlacementHighlight = false
    private var isKanaPresentedInBounds = false
    private var romajiLabelCenterYConstraint: NSLayoutConstraint!
    private var kanaSlotCenterYConstraint: NSLayoutConstraint!

    /// Tracks which border palette is currently applied, so trait changes can re-resolve `.cgColor`.
    private enum BorderState { case `default`, dropHighlight, success }
    private var currentBorderState: BorderState = .default

    init(choiceValue: String, typography: MatchCardTypography) {
        self.choiceValue = choiceValue
        self.typography = typography
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        KanaSoundMatchDragManager.shared.unregisterDropTarget(self)
    }

    func highlightAsDropTarget() {
        if !isKanaPresentedInBounds {
            setKanaPresentedInBounds(true, animated: true)
        }
        currentBorderState = .dropHighlight
        soundPanel.backgroundColor = KanaSoundMatchStyle.dropHighlightFill
        soundPanel.layer.borderWidth = KanaSoundMatchStyle.dropHighlightBorderWidth
        soundPanel.layer.borderColor = KanaSoundMatchStyle.dropHighlightBorder.cgColor
    }

    func unhighlightAsDropTarget() {
        guard !keepsPlacementHighlight || KanaSoundMatchDragManager.shared.isDragging else { return }
        if isKanaPresentedInBounds {
            setKanaPresentedInBounds(false, animated: true)
        }
        applyDefaultSoundPanelAppearance()
    }

    func hitFrameInContainer(_ container: UIView) -> CGRect {
        stableDropZoneFrame(in: container)
    }

    func kanaLandingCenter(in container: UIView) -> CGPoint {
        let slotFrame = stableSlotFrame(in: container, presented: true)
        return CGPoint(x: slotFrame.midX, y: slotFrame.midY)
    }

    func placeDraggedContent(_ text: String) {
        keepsPlacementHighlight = true
        setKanaPresentedInBounds(true, animated: false)
        currentBorderState = .dropHighlight
        soundPanel.backgroundColor = KanaSoundMatchStyle.dropHighlightFill
        soundPanel.layer.borderWidth = KanaSoundMatchStyle.dropHighlightBorderWidth
        soundPanel.layer.borderColor = KanaSoundMatchStyle.dropHighlightBorder.cgColor
    }

    func clearPlacedContent() {
        keepsPlacementHighlight = false
        kanaSlotView.subviews.forEach { $0.removeFromSuperview() }
        setKanaPresentedInBounds(false, animated: false)
        applyDefaultSoundPanelAppearance()
    }

    func embedKanaCard(_ card: UIView) {
        card.translatesAutoresizingMaskIntoConstraints = false
        kanaSlotView.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: kanaSlotView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: kanaSlotView.centerYAnchor),
        ])
    }

    func applySuccessAppearance() {
        keepsPlacementHighlight = true
        currentBorderState = .success
        soundPanel.backgroundColor = KanaSoundMatchStyle.successFill
        soundPanel.layer.borderWidth = KanaSoundMatchStyle.dropHighlightBorderWidth
        soundPanel.layer.borderColor = KanaSoundMatchStyle.successBorder.cgColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        soundPanel.translatesAutoresizingMaskIntoConstraints = false
        soundPanel.layer.cornerRadius = KanaSoundMatchStyle.soundCardCornerRadius
        soundPanel.layer.cornerCurve = .continuous
        applyDefaultSoundPanelAppearance()

        choiceLabel.text = choiceValue
        choiceLabel.textAlignment = .center
        choiceLabel.textColor = .label
        choiceLabel.adjustsFontForContentSizeCategory = true
        let textStyle: UIFont.TextStyle = typography == .hiragana ? .title1 : .title2
        choiceLabel.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: .systemFont(ofSize: typography.panelFontSize, weight: .semibold)
        )
        choiceLabel.translatesAutoresizingMaskIntoConstraints = false
        soundPanel.addSubview(choiceLabel)

        kanaSlotView.translatesAutoresizingMaskIntoConstraints = false
        kanaSlotView.isUserInteractionEnabled = true
        kanaSlotView.backgroundColor = .clear
        kanaSlotView.layer.cornerRadius = KanaSoundMatchStyle.kanaCardCornerRadius
        kanaSlotView.layer.cornerCurve = .continuous
        kanaSlotView.layer.shadowColor = UIColor.black.cgColor
        kanaSlotView.layer.shadowRadius = 4
        kanaSlotView.layer.shadowOffset = CGSize(width: 0, height: 2)
        kanaSlotView.layer.shadowOpacity = 0

        addSubview(soundPanel)
        addSubview(kanaSlotView)

        let side = KanaSoundMatchStyle.kanaCardSide
        NSLayoutConstraint.activate([
            soundPanel.topAnchor.constraint(equalTo: topAnchor),
            soundPanel.leadingAnchor.constraint(equalTo: leadingAnchor),
            soundPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            soundPanel.widthAnchor.constraint(equalTo: soundPanel.heightAnchor),

            choiceLabel.centerXAnchor.constraint(equalTo: soundPanel.centerXAnchor),
            {
                let c = choiceLabel.centerYAnchor.constraint(equalTo: soundPanel.centerYAnchor)
                romajiLabelCenterYConstraint = c
                return c
            }(),

            kanaSlotView.centerXAnchor.constraint(equalTo: soundPanel.centerXAnchor),
            {
                let c = kanaSlotView.centerYAnchor.constraint(
                    equalTo: soundPanel.bottomAnchor,
                    constant: -KanaSoundMatchStyle.kanaSlotOffsetY
                )
                kanaSlotCenterYConstraint = c
                return c
            }(),
            kanaSlotView.widthAnchor.constraint(equalToConstant: side),
            kanaSlotView.heightAnchor.constraint(equalToConstant: side),

            heightAnchor.constraint(
                equalTo: widthAnchor,
                multiplier: 1,
                constant: side / 2 - KanaSoundMatchStyle.kanaSlotOffsetY
            ),
        ])

        accessibilityLabel = choiceValue
        accessibilityHint = "Drop target for matching card"
        isAccessibilityElement = true
    }

    private func applyDefaultSoundPanelAppearance() {
        currentBorderState = .default
        soundPanel.backgroundColor = KanaSoundMatchStyle.cardBackground
        soundPanel.layer.borderWidth = KanaSoundMatchStyle.soundCardBorderWidth
        soundPanel.layer.borderColor = KanaSoundMatchStyle.cardBorder.cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // `.cgColor` froze the previous trait collection — re-resolve for the new one.
        let resolved: UIColor
        switch currentBorderState {
        case .default: resolved = KanaSoundMatchStyle.cardBorder
        case .dropHighlight: resolved = KanaSoundMatchStyle.dropHighlightBorder
        case .success: resolved = KanaSoundMatchStyle.successBorder
        }
        soundPanel.layer.borderColor = resolved.resolvedColor(with: traitCollection).cgColor
    }

    private func setKanaPresentedInBounds(_ presented: Bool, animated: Bool) {
        guard presented != isKanaPresentedInBounds else { return }
        isKanaPresentedInBounds = presented

        // During drag, animate with transforms so Auto Layout passes do not block the ghost.
        if KanaSoundMatchDragManager.shared.isDragging && animated {
            applyPresentationTransform(presented, animated: true)
            return
        }

        choiceLabel.transform = .identity
        kanaSlotView.transform = .identity

        kanaSlotCenterYConstraint.constant = presented
            ? -(KanaSoundMatchStyle.kanaSlotOffsetY + KanaSoundMatchStyle.kanaSlotExtraOffsetY)
            : -KanaSoundMatchStyle.kanaSlotOffsetY
        romajiLabelCenterYConstraint.constant = presented
            ? -KanaSoundMatchStyle.romajiLabelShiftY
            : 0

        let updates = { self.layoutIfNeeded() }
        guard animated else {
            updates()
            return
        }
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: updates
        )
    }

    private func applyPresentationTransform(_ presented: Bool, animated: Bool) {
        let labelShift = presented ? -KanaSoundMatchStyle.romajiLabelShiftY : 0
        let slotShift = presented ? -KanaSoundMatchStyle.kanaSlotExtraOffsetY : 0
        let updates = {
            self.choiceLabel.transform = CGAffineTransform(translationX: 0, y: labelShift)
            self.kanaSlotView.transform = CGAffineTransform(translationX: 0, y: slotShift)
        }
        guard animated else {
            updates()
            return
        }
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: updates
        )
    }

    /// Hover hit-testing uses fixed geometry so highlight layout animations cannot move the drop zone.
    private func stableDropZoneFrame(in container: UIView) -> CGRect {
        let panel = soundPanel.convert(soundPanel.bounds, to: container)
        return panel
            .union(stableSlotFrame(in: container, presented: false))
            .union(stableSlotFrame(in: container, presented: true))
    }

    private func stableSlotFrame(in container: UIView, presented: Bool) -> CGRect {
        let panel = soundPanel.convert(soundPanel.bounds, to: container)
        let side = KanaSoundMatchStyle.kanaCardSide
        let offset = presented
            ? KanaSoundMatchStyle.kanaSlotOffsetY + KanaSoundMatchStyle.kanaSlotExtraOffsetY
            : KanaSoundMatchStyle.kanaSlotOffsetY
        let centerY = panel.maxY - offset
        return CGRect(
            x: panel.midX - side / 2,
            y: centerY - side / 2,
            width: side,
            height: side
        )
    }
}

// MARK: - Kana card (drag source)

private final class KanaDragCardView: UIView, KanaSoundDragSource, KanaSoundMatchDragDelegate {

    let draggedText: String
    let correctChoice: String
    private let typography: MatchCardTypography

    var onPlaced: ((KanaSoundDropTarget) -> Void)?

    private let textLabel = UILabel()
    private let panGesture = UIPanGestureRecognizer()
    private var idleTiltApplied = false
    private var dropRotationRadians: CGFloat?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    init(draggedText: String, correctChoice: String, typography: MatchCardTypography) {
        self.draggedText = draggedText
        self.correctChoice = correctChoice
        self.typography = typography
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hideForDrag() {
        alpha = 0
        if placementHost?.currentPlacedDropTarget() == nil {
            clearDropRotation()
        }
    }

    func showAfterDrag() {
        alpha = 1
        isUserInteractionEnabled = true
        if placementHost?.currentPlacedDropTarget() == nil {
            applyIdleTilt()
            idleTiltApplied = true
        }
    }

    func homeCenter(in container: UIView) -> CGPoint {
        convert(CGPoint(x: bounds.midX, y: bounds.midY), to: container)
    }

    func dragDidPlace(draggedText: String, on target: KanaSoundDropTarget) {
        onPlaced?(target)
    }

    func placedTransformForDrop() -> CGAffineTransform {
        placedTransform()
    }

    func dockTransformForDrag() -> CGAffineTransform {
        dockTransform()
    }

    func makeDragGhostView() -> UIView {
        MatchDragGhostView(
            text: draggedText,
            fontSize: typography.dragFontSize,
            weight: typography.dragFontWeight
        )
    }

    func applyRestingAppearance(inDock: Bool, animated: Bool = false) {
        applyTypography()
        idleTiltApplied = true
        if inDock {
            clearDropRotation()
        }
        let targetTransform = inDock ? dockTransform() : placedTransform()
        guard animated else {
            transform = targetTransform
            return
        }
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = targetTransform
        }
    }

    func applyPlacedAppearance() {
        applyTypography()
        idleTiltApplied = true
        transform = placedTransform()
        alpha = 1
        isUserInteractionEnabled = true
    }

    func animateSuccessBounce(
        successSound: ExperimentFeedbackSound.PreparedSuccessSound,
        completion: (() -> Void)? = nil
    ) {
        animateKanaSoundMatchBounce(
            configuration: .production,
            baseTransform: placedTransform(),
            successSound: successSound,
            completion: completion
        )
    }

    private func applyTypography() {
        let metrics = UIFontMetrics(forTextStyle: .title1)
        textLabel.font = metrics.scaledFont(
            for: .systemFont(ofSize: typography.dragFontSize, weight: typography.dragFontWeight)
        )
    }

    private func dockTransform() -> CGAffineTransform {
        CGAffineTransform(rotationAngle: -.pi / 90)
    }

    private func placedTransform() -> CGAffineTransform {
        let radians = resolvedDropRotationRadians()
        let rotation = CGAffineTransform(rotationAngle: radians)
        let scale = KanaSoundMatchStyle.placedCardScale
        return rotation.scaledBy(x: scale, y: scale)
    }

    private func resolvedDropRotationRadians() -> CGFloat {
        if let dropRotationRadians {
            return dropRotationRadians
        }
        let degrees = CGFloat.random(
            in: -KanaSoundMatchStyle.dropRotationRangeDegrees ... KanaSoundMatchStyle.dropRotationRangeDegrees
        )
        let radians = degrees * .pi / 180
        dropRotationRadians = radians
        return radians
    }

    private func clearDropRotation() {
        dropRotationRadians = nil
    }

    private func applyIdleTilt() {
        transform = dockTransform()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: KanaSoundMatchStyle.kanaCardCornerRadius
        ).cgPath
        if !idleTiltApplied,
           !KanaSoundMatchDragManager.shared.isDragging,
           placementHost?.currentPlacedDropTarget() == nil {
            applyIdleTilt()
            idleTiltApplied = true
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = KanaSoundMatchStyle.dragCardBackground
        layer.cornerRadius = KanaSoundMatchStyle.kanaCardCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = false
        applyDragCardBorder()
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)

        textLabel.text = draggedText
        textLabel.textAlignment = .center
        textLabel.textColor = .label
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        let width = widthAnchor.constraint(equalToConstant: KanaSoundMatchStyle.kanaCardSide)
        let height = heightAnchor.constraint(equalToConstant: KanaSoundMatchStyle.kanaCardSide)
        widthConstraint = width
        heightConstraint = height

        NSLayoutConstraint.activate([
            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            width,
            height,
        ])
        applyRestingAppearance(inDock: true)

        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        accessibilityLabel = draggedText
        accessibilityHint = "Drag onto the matching card"
        isAccessibilityElement = true
    }

    private func applyDragCardBorder() {
        layer.borderWidth = KanaSoundMatchStyle.dragCardBorderWidth
        layer.borderColor = KanaSoundMatchStyle.cardBorder.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyDragCardBorder()
    }

    weak var placementHost: KanaSoundMatchExperimentViewController?

    func placedDropTargetForSnapBack() -> KanaSoundDropTarget? {
        placementHost?.currentPlacedDropTarget()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = window else { return }
        let container = window
        let location = gesture.location(in: container)

        switch gesture.state {
        case .began:
            KanaSoundMatchDragManager.shared.startDragging(
                from: self,
                touchLocation: location,
                in: container
            )
        case .changed:
            KanaSoundMatchDragManager.shared.updateDrag(to: location)
        case .ended:
            KanaSoundMatchDragManager.shared.endDrag(at: location, in: container)
        case .cancelled, .failed:
            KanaSoundMatchDragManager.shared.cancelDrag()
        default:
            break
        }
    }
}

private final class MatchDragGhostView: UIView {
    init(text: String, fontSize: CGFloat, weight: UIFont.Weight) {
        super.init(frame: .zero)
        backgroundColor = KanaSoundMatchStyle.dragCardBackground
        layer.cornerRadius = KanaSoundMatchStyle.kanaCardCornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = KanaSoundMatchStyle.dragCardBorderWidth
        layer.borderColor = KanaSoundMatchStyle.cardBorder
            .resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.font = .systemFont(ofSize: fontSize, weight: weight)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - View controller

final class KanaSoundMatchExperimentViewController: LessonStepViewController {

    var onStepResult: ((String, Bool) -> Void)?

    private var round: KanaSoundMatchRound
    private var stepIndex: Int
    private var totalSteps: Int

    private var hasSucceeded = false
    private weak var placedOnTarget: SoundCardView?
    private let pronunciationPlayer = KanaPronunciationPlayer()

    private let gridStack = UIStackView()
    private let kanaDock = UIView()
    private let kanaCard: KanaDragCardView

    private var soundCards: [SoundCardView] = []

    init(round: KanaSoundMatchRound, stepIndex: Int, totalSteps: Int) {
        self.round = round
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        let dragTypography: MatchCardTypography = round.direction == .kanaToRomaji ? .hiragana : .romaji
        kanaCard = KanaDragCardView(
            draggedText: round.draggedText,
            correctChoice: round.correctChoice,
            typography: dragTypography
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStepIndex(_ stepIndex: Int, totalSteps: Int) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ExperimentFeedbackSound.prepareDragHoverClick()
        configureLayout()
        rebuildRound()
        updateCheckButtonState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncDropTargetRegistration(active: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pronunciationPlayer.stop()
        syncDropTargetRegistration(active: false)
    }

    private func syncDropTargetRegistration(active: Bool) {
        for card in soundCards {
            if active {
                KanaSoundMatchDragManager.shared.registerDropTarget(card)
            } else {
                KanaSoundMatchDragManager.shared.unregisterDropTarget(card)
            }
        }
    }

    private func configureLayout() {
        let instructionText = round.direction == .kanaToRomaji
            ? "Drag the \(KanaScript.detecting(in: round.draggedText).displayName) to its matching sound."
            : "Drag the sound to its matching \(KanaScript.detecting(in: round.correctChoice).displayName)."
        configureInstruction(instructionText)

        gridStack.axis = .vertical
        gridStack.spacing = KanaSoundMatchStyle.gridSpacing
        gridStack.distribution = .fill
        gridStack.alignment = .fill

        kanaDock.translatesAutoresizingMaskIntoConstraints = false
        kanaDock.addSubview(kanaCard)
        kanaCard.onPlaced = { [weak self] target in
            self?.handleKanaPlaced(on: target)
        }
        kanaCard.placementHost = self

        configureCTA(
            .custom(title: "Check", style: .blue, accessibilityLabel: "Check match"),
            target: self,
            action: #selector(primaryButtonTapped)
        )

        let contentStack = makeLessonContentStack(
            belowInstruction: [gridStack, kanaDock],
            afterInstructionSpacing: 24
        )
        contentStack.setCustomSpacing(KanaSoundMatchStyle.gridToKanaSpacing, after: gridStack)

        installLessonContent(
            contentStack,
            horizontalInset: LessonStepLayout.instructionHeaderHorizontalInset
        )

        NSLayoutConstraint.activate([
            kanaCard.centerXAnchor.constraint(equalTo: kanaDock.centerXAnchor),
            kanaCard.centerYAnchor.constraint(equalTo: kanaDock.centerYAnchor),
            kanaDock.heightAnchor.constraint(equalToConstant: KanaSoundMatchStyle.kanaCardSide),
        ])
    }

    private func rebuildRound() {
        soundCards.forEach { $0.removeFromSuperview() }
        soundCards = []
        gridStack.arrangedSubviews.forEach { gridStack.removeArrangedSubview($0); $0.removeFromSuperview() }

        let pairs = stride(from: 0, to: round.choices.count, by: 2).map {
            Array(round.choices[$0 ..< min($0 + 2, round.choices.count)])
        }

        for rowSounds in pairs {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = KanaSoundMatchStyle.gridSpacing
            row.distribution = .fillEqually
            row.alignment = .top

            let gridTypography: MatchCardTypography = round.direction == .kanaToRomaji ? .romaji : .hiragana
            for choice in rowSounds {
                let card = SoundCardView(choiceValue: choice, typography: gridTypography)
                soundCards.append(card)
                row.addArrangedSubview(card)
            }
            gridStack.addArrangedSubview(row)
        }

    }

    func currentPlacedDropTarget() -> KanaSoundDropTarget? {
        placedOnTarget
    }

    private func canCheck() -> Bool {
        placedOnTarget != nil
    }

    private func updateCheckButtonState() {
        primaryButton.isEnabled = canCheck() && !hasSucceeded
    }

    @objc private func primaryButtonTapped() {
        checkAnswer()
    }

    private func checkAnswer() {
        guard !hasSucceeded, let placed = placedOnTarget else { return }

        if placed.choiceValue == round.correctChoice {
            hasSucceeded = true
            onStepResult?(round.primaryKana, true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            kanaCard.isUserInteractionEnabled = false
            kanaDock.isHidden = true
            updateCheckButtonState()
            showSuccess(on: placed)
        } else {
            onStepResult?(round.primaryKana, false)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
            clearPlacement()
        }
    }

    private func showSuccess(on placed: SoundCardView) {
        placed.applySuccessAppearance()
        let successSound = ExperimentFeedbackSound.prepareSuccess(for: .kanaSoundMatch)
        kanaCard.animateSuccessBounce(successSound: successSound) { [weak self] in
            self?.scheduleAutoAdvanceAfterSuccess()
        }
    }

    private func scheduleAutoAdvanceAfterSuccess() {
        guard hasSucceeded else { return }
        scheduleAutoAdvance()
    }

    private func clearPlacement() {
        soundCards.forEach { $0.clearPlacedContent() }
        placedOnTarget = nil
        returnKanaCardToDock()
        updateCheckButtonState()
    }

    private func returnKanaCardToDock() {
        kanaCard.removeFromSuperview()
        kanaDock.isHidden = false
        kanaDock.addSubview(kanaCard)
        NSLayoutConstraint.activate([
            kanaCard.centerXAnchor.constraint(equalTo: kanaDock.centerXAnchor),
            kanaCard.centerYAnchor.constraint(equalTo: kanaDock.centerYAnchor),
        ])
        kanaCard.applyRestingAppearance(inDock: true, animated: true)
        kanaCard.showAfterDrag()
        kanaCard.isUserInteractionEnabled = true
    }

    private func moveKanaCard(to soundCard: SoundCardView) {
        kanaCard.removeFromSuperview()
        kanaDock.isHidden = true
        soundCard.embedKanaCard(kanaCard)
        soundCard.placeDraggedContent(round.draggedText)
        kanaCard.applyPlacedAppearance()
        kanaCard.isUserInteractionEnabled = !hasSucceeded
    }

    private func handleKanaPlaced(on target: KanaSoundDropTarget) {
        guard !hasSucceeded, let card = target as? SoundCardView else { return }

        soundCards.forEach { existing in
            if existing !== card {
                existing.clearPlacedContent()
            }
        }
        placedOnTarget = card
        moveKanaCard(to: card)
        pronunciationPlayer.play(kana: round.droppedKanaToPlay(on: card.choiceValue))
        updateCheckButtonState()
    }
}
