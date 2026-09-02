//
//  LanguageProgressSnakeExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: Duolingo-style lesson path. Glass stones follow a sine
//  wave in a UICollectionView (custom layout + cell reuse). A compact tuner
//  sheet live-adjusts spacing, frequency, and amplitude.
//

import UIKit

// MARK: - Tuning

private struct LessonPathConfiguration: Equatable {
    var spacing: CGFloat
    var frequency: CGFloat
    var amplitude: CGFloat
    var nodeSize: CGFloat
    var phase: CGFloat

    static let `default` = LessonPathConfiguration(
        spacing: 33,
        frequency: 0.89,
        amplitude: 1.00,
        nodeSize: 120,
        phase: 0
    )

    static let haloInset: CGFloat = 14
    static let haloBorderWidth: CGFloat = 9
    static let unitSeparatorHeight: CGFloat = 64
    static let headerHeight: CGFloat = 86
    static let headerSpacing: CGFloat = 28
    static let lockedScale: CGFloat = 0.84
    static let lessonPartCount = 5
    static let stoneZPosition: CGFloat = 1
    static let tipZPosition: CGFloat = 8
    static let headerZPosition: CGFloat = 30

    static var burnedYellow: UIColor {
        PrimaryButton.appearance(for: .yellow).titleColor
    }

    fileprivate var topInset: CGFloat { 12 }
    fileprivate var bottomInset: CGFloat { 48 }
    fileprivate var horizontalInset: CGFloat { 22 }

    func xCenter(for index: CGFloat, width: CGFloat) -> CGFloat {
        let halfNode = nodeSize / 2
        let maxSwing = max(0, width / 2 - horizontalInset - halfNode)
        return width / 2 + maxSwing * amplitude * sin(index * frequency + phase)
    }

    static func iconPointSize(for nodeSize: CGFloat) -> CGFloat {
        max(16, nodeSize * 0.29)
    }
}

private enum PathTuningSliderSpec: CaseIterable {
    case spacing
    case frequency
    case amplitude
    case nodeSize
    case phase

    var title: String {
        switch self {
        case .spacing: return "Space between items"
        case .frequency: return "Frequency"
        case .amplitude: return "Amplitude"
        case .nodeSize: return "Stone size"
        case .phase: return "Phase"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .spacing: return 8 ... 80
        case .frequency: return 0.20 ... 1.60
        case .amplitude: return 0 ... 1
        case .nodeSize: return 52 ... 160
        case .phase: return -Float.pi ... Float.pi
        }
    }

    var step: Float {
        switch self {
        case .spacing, .nodeSize: return 1
        case .frequency, .amplitude, .phase: return 0.01
        }
    }
}

// MARK: - Experiment

final class LanguageProgressSnakeExperimentViewController: UIViewController {

    private var configuration = LessonPathConfiguration.default
    private let units = PathUnit.sampleCurriculum
    private var selectedIndexPath = PathUnit.initialCurrentIndexPath
    private var isLessonTipPresented = false
    private var visibleUnitIndex = 0
    private var tipPlacedBelow: Bool?
    private var isAnimatingTipPlacement = false

    private let lessonTipView = LessonTitleTipView()
    private let sineLayout = LessonSinePathLayout()
    private var collectionView: UICollectionView!
    private weak var tuningSheet: LessonPathTuningSheetViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            primaryAction: UIAction { [weak self] _ in
                self?.presentTuningSheet()
            }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Tune path"

        configureCollectionView()

        collectionView.topEdgeEffect.style = .soft
    }

    private func configureCollectionView() {
        sineLayout.configuration = configuration
        sineLayout.unitLengths = units.map(\.lessons.count)
        sineLayout.lockedFlags = units.flatMap { $0.lessons.map { $0.state == .locked } }
        sineLayout.register(
            PathDecorationView.self,
            forDecorationViewOfKind: PathDecorationView.kind
        )
        sineLayout.register(
            UnitDividerDecorationView.self,
            forDecorationViewOfKind: UnitDividerDecorationView.kind
        )

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: sineLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = ExperimentPalette.pageBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LessonStoneCell.self, forCellWithReuseIdentifier: LessonStoneCell.reuseID)
        collectionView.register(
            PathUnitHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: PathUnitHeaderView.reuseID
        )
        collectionView.contentInsetAdjustmentBehavior = .never
        lessonTipView.isHidden = true
        lessonTipView.layer.zPosition = LessonPathConfiguration.tipZPosition
        lessonTipView.onDismiss = { [weak self] in
            self?.dismissLessonTip()
        }
        lessonTipView.onStart = { [weak self] in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self?.dismissLessonTip()
        }

        view.addSubview(collectionView)
        collectionView.addSubview(lessonTipView)

        let dismissTipTap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTipTap(_:)))
        dismissTipTap.cancelsTouchesInView = false
        dismissTipTap.delegate = self
        collectionView.addGestureRecognizer(dismissTipTap)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let topInset = view.safeAreaInsets.top + 12
        let bottomInset = view.safeAreaInsets.bottom
        guard collectionView.contentInset.top != topInset
            || collectionView.contentInset.bottom != bottomInset
        else { return }
        collectionView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        collectionView.verticalScrollIndicatorInsets = collectionView.contentInset
    }

    private func applyConfiguration(_ configuration: LessonPathConfiguration) {
        self.configuration = configuration
        sineLayout.configuration = configuration
        sineLayout.lockedFlags = units.flatMap { $0.lessons.map { $0.state == .locked } }
        sineLayout.invalidateLayout()
        reconfigureVisibleStones()
        if isLessonTipPresented {
            updateLessonTipPosition()
        }
    }

    private func lesson(at indexPath: IndexPath) -> PathLesson {
        units[indexPath.section].lessons[indexPath.item]
    }

    private func reconfigureVisibleStones() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? LessonStoneCell else { continue }
            cell.apply(
                lesson: lesson(at: indexPath),
                selected: isLessonTipPresented && indexPath == selectedIndexPath,
                nodeSize: configuration.nodeSize
            )
        }
    }

    private func selectLesson(at indexPath: IndexPath) {
        guard units.indices.contains(indexPath.section),
              units[indexPath.section].lessons.indices.contains(indexPath.item)
        else { return }

        let alreadySelected = indexPath == selectedIndexPath && isLessonTipPresented
        selectedIndexPath = indexPath
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if alreadySelected {
            dismissLessonTip()
        } else {
            showLessonTip(for: indexPath)
        }
    }

    private func updateVisibleUnitFromScroll() {
        let pinY = collectionView.contentOffset.y + collectionView.contentInset.top
        let section = sineLayout.stuckSection(at: pinY)
        guard section != visibleUnitIndex else { return }
        visibleUnitIndex = section
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func showLessonTip(for indexPath: IndexPath) {
        let unit = units[indexPath.section]
        let lesson = unit.lessons[indexPath.item]
        lessonTipView.apply(
            title: lesson.title,
            subtitle: "Unit \(indexPath.section + 1) • Lesson \(indexPath.item + 1)",
            hasProgress: lesson.completedParts > 0
        )
        isLessonTipPresented = true
        tipPlacedBelow = nil
        isAnimatingTipPlacement = false
        lessonTipView.isHidden = false
        reconfigureVisibleStones()
        collectionView.layoutIfNeeded()
        updateLessonTipPosition()
        lessonTipView.showWithAnimation()
    }

    private func dismissLessonTip() {
        guard isLessonTipPresented else { return }
        isLessonTipPresented = false
        tipPlacedBelow = nil
        isAnimatingTipPlacement = false
        reconfigureVisibleStones()
        lessonTipView.dismissWithAnimation { [weak self] in
            self?.lessonTipView.isHidden = true
        }
    }

    private func updateLessonTipPosition() {
        guard isLessonTipPresented, !isAnimatingTipPlacement else { return }
        let stoneFrame = collectionView.cellForItem(at: selectedIndexPath)?.frame
            ?? sineLayout.layoutAttributesForItem(at: selectedIndexPath)?.frame
        guard let stoneFrame else { return }

        let cardWidth = min(268, collectionView.bounds.width - 48)
        let tipSize = lessonTipView.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let visibleBottom = collectionView.contentOffset.y + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        let gap: CGFloat = 10
        let hysteresis: CGFloat = 28
        let neededBelow = stoneFrame.maxY + gap + tipSize.height
        let placeBelow: Bool
        if let tipPlacedBelow {
            placeBelow = tipPlacedBelow
                ? neededBelow < visibleBottom + hysteresis
                : neededBelow + hysteresis < visibleBottom
        } else {
            placeBelow = neededBelow < visibleBottom
        }

        let originY = placeBelow
            ? stoneFrame.maxY + gap
            : stoneFrame.minY - tipSize.height - gap
        var originX = stoneFrame.midX - tipSize.width / 2
        originX = min(max(20, originX), collectionView.bounds.width - tipSize.width - 20)
        let targetFrame = CGRect(origin: CGPoint(x: originX, y: originY), size: tipSize)
        let flipped = tipPlacedBelow != nil && tipPlacedBelow != placeBelow
        tipPlacedBelow = placeBelow

        let applyPlacement = {
            self.lessonTipView.frame = targetFrame
            self.lessonTipView.setArrowEdge(placeBelow ? .top : .bottom)
            self.lessonTipView.setSourceCenterX(stoneFrame.midX)
            self.lessonTipView.layoutIfNeeded()
        }

        if flipped {
            isAnimatingTipPlacement = true
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.35,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                applyPlacement()
            } completion: { _ in
                self.isAnimatingTipPlacement = false
                self.updateLessonTipPosition()
            }
        } else {
            applyPlacement()
        }
        restackLessonTip()
    }

    private func restackLessonTip() {
        lessonTipView.layer.zPosition = LessonPathConfiguration.tipZPosition
        for subview in collectionView.subviews {
            if subview is PathUnitHeaderView {
                subview.layer.zPosition = LessonPathConfiguration.headerZPosition
            }
        }
    }

    private func presentTuningSheet() {
        if let tuningSheet, tuningSheet.presentingViewController != nil {
            return
        }

        let sheet = LessonPathTuningSheetViewController(configuration: configuration)
        sheet.onChange = { [weak self] configuration in
            self?.applyConfiguration(configuration)
        }
        sheet.onReset = { [weak self] in
            guard let self else { return }
            self.applyConfiguration(.default)
            self.tuningSheet?.sync(configuration: .default)
        }
        tuningSheet = sheet

        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            let detent = UISheetPresentationController.Detent.custom(identifier: .init("pathTune")) { _ in
                420
            }
            presentation.detents = [detent]
            presentation.largestUndimmedDetentIdentifier = detent.identifier
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = false
            presentation.preferredCornerRadius = 28
        }
        present(sheet, animated: true)
    }
}

// MARK: - Collection view

extension LanguageProgressSnakeExperimentViewController: UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        units.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        units[section].lessons.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LessonStoneCell.reuseID,
            for: indexPath
        ) as! LessonStoneCell
        cell.apply(
            lesson: lesson(at: indexPath),
            selected: isLessonTipPresented && indexPath == selectedIndexPath,
            nodeSize: configuration.nodeSize
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: PathUnitHeaderView.reuseID,
            for: indexPath
        ) as! PathUnitHeaderView
        header.apply(unit: units[indexPath.section], animated: false)
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        selectLesson(at: indexPath)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleUnitFromScroll()
        if !lessonTipView.isHidden {
            updateLessonTipPosition()
        }
    }

    @objc private func handleDismissTipTap(_ gesture: UITapGestureRecognizer) {
        guard isLessonTipPresented, gesture.state == .ended else { return }
        let point = gesture.location(in: collectionView)
        if lessonTipView.frame.contains(point) {
            dismissLessonTip()
            return
        }
        if collectionView.indexPathForItem(at: point) != nil {
            return
        }
        dismissLessonTip()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isLessonTipPresented
    }
}

// MARK: - Model

private struct PathLesson {
    enum State {
        case completed
        case current
        case locked
    }

    let title: String
    let symbolName: String
    let thumbnailName: String?
    let state: State
    let completedParts: Int

    init(
        title: String,
        symbolName: String,
        thumbnailName: String?,
        state: State,
        completedParts: Int = 0
    ) {
        self.title = title
        self.symbolName = symbolName
        self.thumbnailName = thumbnailName
        self.state = state
        self.completedParts = completedParts
    }
}

private struct PathUnit {
    let eyebrow: String
    let title: String
    let glowColor: DialogueBubbleUnderglowColor
    let lessons: [PathLesson]

    static var initialCurrentIndexPath: IndexPath {
        IndexPath(item: 2, section: 0)
    }

    static let sampleCurriculum: [PathUnit] = [
        PathUnit(
            eyebrow: "SECTION 1, UNIT 1",
            title: "Everyday conversations",
            glowColor: .yellow,
            lessons: [
                PathLesson(title: "At the Train Station", symbolName: "tram.fill", thumbnailName: "train-station", state: .completed),
                PathLesson(title: "At the Library", symbolName: "book.fill", thumbnailName: "at-the-library", state: .completed),
                PathLesson(title: "At the Convenience Store", symbolName: "basket.fill", thumbnailName: "at-the-convenient-store", state: .current, completedParts: 2),
                PathLesson(title: "Asking Directions", symbolName: "map.fill", thumbnailName: "asking-directions", state: .locked),
                PathLesson(title: "Greetings", symbolName: "hand.wave.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Café", symbolName: "cup.and.saucer.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Restaurant", symbolName: "fork.knife", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Hotel", symbolName: "bed.double.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Shopping", symbolName: "bag.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "On the Phone", symbolName: "phone.fill", thumbnailName: nil, state: .locked),
            ]
        ),
        PathUnit(
            eyebrow: "SECTION 1, UNIT 2",
            title: "Around town",
            glowColor: .blue,
            lessons: [
                PathLesson(title: "Weather", symbolName: "cloud.sun.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Travel", symbolName: "airplane", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Bus Stop", symbolName: "bus.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Post Office", symbolName: "envelope.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Bank", symbolName: "building.columns.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Hospital", symbolName: "cross.case.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Pharmacy", symbolName: "pills.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At the Park", symbolName: "leaf.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "At School", symbolName: "graduationcap.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Town review", symbolName: "star.fill", thumbnailName: nil, state: .locked),
            ]
        ),
        PathUnit(
            eyebrow: "SECTION 1, UNIT 3",
            title: "Daily life",
            glowColor: .yellow,
            lessons: [
                PathLesson(title: "Morning routine", symbolName: "sunrise.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Cooking", symbolName: "frying.pan.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Family", symbolName: "figure.2.and.child.holdinghands", thumbnailName: nil, state: .locked),
                PathLesson(title: "Hobbies", symbolName: "paintpalette.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "The weekend", symbolName: "calendar", thumbnailName: nil, state: .locked),
                PathLesson(title: "At work", symbolName: "briefcase.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Friends", symbolName: "person.2.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Feelings", symbolName: "heart.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Making plans", symbolName: "clock.fill", thumbnailName: nil, state: .locked),
                PathLesson(title: "Unit project", symbolName: "flag.fill", thumbnailName: nil, state: .locked),
            ]
        ),
    ]
}

// MARK: - Unit header

private final class PathUnitHeaderView: UICollectionReusableView {

    static let reuseID = "PathUnitHeaderView"

    private static let cornerRadius: CGFloat = 18

    private let glassGlowView = UIView()
    private let underglowGradientLayer = CAGradientLayer()
    private let glassView = LiquidGlassEffectView.makeContainer()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private var underglowConfiguration = DialogueBubbleUnderglowConfiguration.default

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = .clear

        glassGlowView.translatesAutoresizingMaskIntoConstraints = true
        glassGlowView.isUserInteractionEnabled = false
        glassGlowView.backgroundColor = .clear
        glassGlowView.clipsToBounds = false
        underglowGradientLayer.type = .radial
        glassGlowView.layer.addSublayer(underglowGradientLayer)

        LiquidGlassEffectView.applyBubbleStyle(to: glassView, cornerRadius: Self.cornerRadius)
        glassView.isUserInteractionEnabled = false

        eyebrowLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = .secondaryLabel

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassGlowView)
        addSubview(glassView)
        addSubview(stack)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        applyUnderglowAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        layer.zPosition = LessonPathConfiguration.headerZPosition
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.zPosition = LessonPathConfiguration.headerZPosition
        layoutUnderglow()
    }

    func apply(unit: PathUnit, animated: Bool) {
        let updateText = {
            self.eyebrowLabel.text = unit.eyebrow
            self.titleLabel.text = unit.title
        }
        if animated {
            UIView.transition(with: self, duration: 0.28, options: .transitionCrossDissolve, animations: updateText)
        } else {
            updateText()
        }
        setGlowColor(unit.glowColor, animated: animated)
    }

    private func setGlowColor(_ color: DialogueBubbleUnderglowColor, animated: Bool) {
        underglowConfiguration.color = color
        let apply = { self.applyUnderglowAppearance() }
        if animated {
            UIView.animate(withDuration: 0.28, animations: apply)
        } else {
            apply()
        }
        setNeedsLayout()
    }

    private func applyUnderglowAppearance() {
        let color = underglowConfiguration.glowUIColor
        let blur = underglowConfiguration.blurRadius
        glassGlowView.alpha = underglowConfiguration.opacity
        if blur <= 0 {
            underglowGradientLayer.colors = [color.cgColor, color.cgColor]
            underglowGradientLayer.locations = [0, 1]
            glassGlowView.layer.shadowOpacity = 0
            glassGlowView.layer.shadowPath = nil
        } else {
            let midStop = max(0.2, min(0.8, 0.55 - blur / 80))
            underglowGradientLayer.colors = [
                color.cgColor,
                color.withAlphaComponent(0.4).cgColor,
                UIColor.clear.cgColor,
            ]
            underglowGradientLayer.locations = [0, NSNumber(value: Float(midStop)), 1]
            glassGlowView.layer.shadowColor = color.cgColor
            glassGlowView.layer.shadowRadius = blur
            glassGlowView.layer.shadowOpacity = 0.5
            glassGlowView.layer.shadowOffset = .zero
        }
        underglowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        underglowGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        underglowGradientLayer.cornerCurve = .continuous
    }

    private func layoutUnderglow() {
        let coreFrame = underglowConfiguration.glowFrame(in: bounds)
        guard coreFrame.width > 0, coreFrame.height > 0 else {
            glassGlowView.frame = .zero
            underglowGradientLayer.frame = .zero
            glassGlowView.layer.shadowPath = nil
            return
        }

        let blur = underglowConfiguration.blurRadius
        let padding = blur > 0 ? blur * 0.75 : 0
        glassGlowView.frame = coreFrame.insetBy(dx: -padding, dy: -padding)
        underglowGradientLayer.frame = glassGlowView.bounds
        underglowGradientLayer.cornerRadius = underglowConfiguration.cornerRadius

        if blur > 0 {
            let shapeRect = CGRect(x: padding, y: padding, width: coreFrame.width, height: coreFrame.height)
            glassGlowView.layer.shadowPath = UIBezierPath(
                roundedRect: shapeRect,
                cornerRadius: underglowConfiguration.cornerRadius
            ).cgPath
        }
    }
}

// MARK: - Sine layout

private final class LessonSinePathLayout: UICollectionViewLayout {

    var configuration = LessonPathConfiguration.default
    var unitLengths: [Int] = []
    var lockedFlags: [Bool] = []

    private var itemAttributes: [[UICollectionViewLayoutAttributes]] = []
    private var headerRestingAttributes: [UICollectionViewLayoutAttributes] = []
    private var pathAttributes: PathDecorationLayoutAttributes?
    private var dividerAttributes: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero

    override var collectionViewContentSize: CGSize { contentSize }

    func stuckSection(at pinY: CGFloat) -> Int {
        var section = 0
        for (index, header) in headerRestingAttributes.enumerated() where header.frame.minY <= pinY + 1 {
            section = index
        }
        return section
    }

    override func prepare() {
        guard let collectionView else { return }
        let width = collectionView.bounds.width
        let size = configuration.nodeSize
        let halo = LessonPathConfiguration.haloInset
        let cellSize = size + halo * 2
        let sectionCount = collectionView.numberOfSections

        itemAttributes = []
        headerRestingAttributes = []
        dividerAttributes = []
        var stoneCenters: [CGPoint] = []
        var stoneRadii: [CGFloat] = []
        var lengths: [Int] = []
        var yCursor = configuration.topInset
        var globalIndex = 0

        for section in 0 ..< sectionCount {
            let header = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                with: IndexPath(item: 0, section: section)
            )
            header.frame = CGRect(
                x: 16,
                y: yCursor,
                width: max(0, width - 32),
                height: LessonPathConfiguration.headerHeight
            )
            header.zIndex = Int(LessonPathConfiguration.headerZPosition)
            headerRestingAttributes.append(header)
            yCursor += LessonPathConfiguration.headerHeight + LessonPathConfiguration.headerSpacing

            let count = collectionView.numberOfItems(inSection: section)
            lengths.append(count)
            var sectionItems: [UICollectionViewLayoutAttributes] = []

            for item in 0 ..< count {
                let locked = lockedFlags[safe: globalIndex] ?? false
                let visualSize = locked ? size * LessonPathConfiguration.lockedScale : size
                let center = CGPoint(
                    x: configuration.xCenter(for: CGFloat(globalIndex), width: width),
                    y: yCursor + size / 2
                )
                stoneCenters.append(center)
                stoneRadii.append(visualSize / 2)

                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: section))
                attributes.frame = CGRect(
                    x: center.x - cellSize / 2,
                    y: center.y - cellSize / 2,
                    width: cellSize,
                    height: cellSize
                )
                attributes.zIndex = Int(LessonPathConfiguration.stoneZPosition)
                sectionItems.append(attributes)

                yCursor += size
                if item < count - 1 {
                    yCursor += configuration.spacing
                }
                globalIndex += 1
            }
            itemAttributes.append(sectionItems)

            if section < sectionCount - 1 {
                let gap = LessonPathConfiguration.unitSeparatorHeight
                let divider = UICollectionViewLayoutAttributes(
                    forDecorationViewOfKind: UnitDividerDecorationView.kind,
                    with: IndexPath(item: 0, section: section)
                )
                divider.frame = CGRect(x: 0, y: yCursor, width: width, height: gap)
                divider.zIndex = 0
                dividerAttributes.append(divider)
                yCursor += gap
            }
        }

        let contentHeight = yCursor + configuration.bottomInset
        let path = PathDecorationLayoutAttributes(
            forDecorationViewOfKind: PathDecorationView.kind,
            with: IndexPath(item: 0, section: 0)
        )
        path.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        path.zIndex = 0
        path.stoneCenters = stoneCenters
        path.stoneRadii = stoneRadii
        path.unitLengths = lengths
        pathAttributes = path

        contentSize = CGSize(width: width, height: contentHeight)
        unitLengths = lengths
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes = itemAttributes.flatMap { $0 }.filter { $0.frame.intersects(rect) }
        attributes.append(contentsOf: pinnedHeaders(intersecting: rect))
        if let pathAttributes, pathAttributes.frame.intersects(rect) {
            attributes.append(pathAttributes)
        }
        attributes.append(contentsOf: dividerAttributes.filter { $0.frame.intersects(rect) })
        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        itemAttributes[safe: indexPath.section]?[safe: indexPath.item]
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }
        return pinnedHeaders(intersecting: CGRect.infinite)[safe: indexPath.section]
    }

    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        switch elementKind {
        case PathDecorationView.kind:
            return pathAttributes
        case UnitDividerDecorationView.kind:
            return dividerAttributes[safe: indexPath.section]
        default:
            return nil
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
    }

    private func pinnedHeaders(intersecting rect: CGRect) -> [UICollectionViewLayoutAttributes] {
        guard let collectionView else { return headerRestingAttributes }
        let pinY = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        return headerRestingAttributes.enumerated().compactMap { section, resting in
            guard let copy = resting.copy() as? UICollectionViewLayoutAttributes else { return nil }
            let nextY = headerRestingAttributes[safe: section + 1]?.frame.minY ?? .greatestFiniteMagnitude
            var frame = copy.frame
            frame.origin.y = min(max(resting.frame.minY, pinY), nextY - frame.height)
            copy.frame = frame
            copy.zIndex = Int(LessonPathConfiguration.headerZPosition)
            return rect.intersects(frame) ? copy : nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class PathDecorationLayoutAttributes: UICollectionViewLayoutAttributes {
    var stoneCenters: [CGPoint] = []
    var stoneRadii: [CGFloat] = []
    var unitLengths: [Int] = []

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! PathDecorationLayoutAttributes
        copy.stoneCenters = stoneCenters
        copy.stoneRadii = stoneRadii
        copy.unitLengths = unitLengths
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PathDecorationLayoutAttributes else { return false }
        return super.isEqual(other)
            && other.stoneCenters == stoneCenters
            && other.stoneRadii == stoneRadii
            && other.unitLengths == unitLengths
    }
}

private final class PathDecorationView: UICollectionReusableView {
    static let kind = "LessonSinePathDecoration"

    private let pathLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        pathLayer.fillColor = nil
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        pathLayer.lineWidth = 6
        layer.addSublayer(pathLayer)
        updatePathColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        guard let attributes = layoutAttributes as? PathDecorationLayoutAttributes else { return }
        pathLayer.frame = CGRect(origin: .zero, size: attributes.frame.size)
        pathLayer.path = Self.makePath(
            centers: attributes.stoneCenters,
            radii: attributes.stoneRadii,
            unitLengths: attributes.unitLengths
        ).cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pathLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updatePathColor()
    }

    private func updatePathColor() {
        pathLayer.strokeColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.22)
                : UIColor(white: 0, alpha: 0.08)
        }.resolvedColor(with: traitCollection).cgColor
    }

    private static func makePath(
        centers: [CGPoint],
        radii: [CGFloat],
        unitLengths: [Int]
    ) -> UIBezierPath {
        let path = UIBezierPath()
        var offset = 0

        for length in unitLengths {
            let endIndex = min(offset + length, centers.count)
            let unitCenters = Array(centers[offset ..< endIndex])
            let unitRadii = Array(radii[offset ..< min(endIndex, radii.count)])
            offset += length
            guard unitCenters.count > 1 else { continue }

            for item in 0 ..< (unitCenters.count - 1) {
                let start = unitCenters[item]
                let end = unitCenters[item + 1]
                let startTrim = (unitRadii[safe: item] ?? 0) + 5
                let endTrim = (unitRadii[safe: item + 1] ?? 0) + 5
                var drawing = false
                for sample in 0 ... 24 {
                    let t = CGFloat(sample) / 24
                    let point = CGPoint(
                        x: start.x + (end.x - start.x) * t,
                        y: start.y + (end.y - start.y) * t
                    )
                    let awayFromStart = hypot(point.x - start.x, point.y - start.y) >= startTrim
                    let awayFromEnd = hypot(point.x - end.x, point.y - end.y) >= endTrim
                    if awayFromStart && awayFromEnd {
                        if drawing {
                            path.addLine(to: point)
                        } else {
                            path.move(to: point)
                            drawing = true
                        }
                    } else {
                        drawing = false
                    }
                }
            }
        }
        return path
    }
}

private final class UnitDividerDecorationView: UICollectionReusableView {
    static let kind = "LessonUnitDivider"

    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = .separator
        addSubview(line)
        NSLayoutConstraint.activate([
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Glass stone cell

private final class LessonStoneCell: UICollectionViewCell {

    static let reuseID = "LessonStoneCell"

    private let haloView = UIView()
    private let progressRing = LessonPartRingView()
    private let shadowView = UIView()
    private let stoneContainer = UIView()
    private let button = UIButton(type: .system)
    private let thumbnailView = UIImageView()
    private let lockOverlay = UIImageView()
    private let badgeView = UIImageView()
    private var currentLesson: PathLesson?
    private var currentNodeSize: CGFloat = LessonPathConfiguration.default.nodeSize
    private var currentSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        contentView.clipsToBounds = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        backgroundConfiguration = .clear()
        automaticallyUpdatesBackgroundConfiguration = false
        selectedBackgroundView = UIView()

        haloView.isUserInteractionEnabled = false
        haloView.backgroundColor = .clear
        haloView.layer.borderWidth = LessonPathConfiguration.haloBorderWidth
        haloView.layer.borderColor = UIColor.systemYellow.cgColor

        progressRing.isUserInteractionEnabled = false
        progressRing.isHidden = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.isUserInteractionEnabled = false

        lockOverlay.contentMode = .scaleAspectFit
        lockOverlay.tintColor = .white
        lockOverlay.image = UIImage(systemName: "lock.fill")
        lockOverlay.isHidden = true
        lockOverlay.isUserInteractionEnabled = false

        shadowView.isUserInteractionEnabled = false
        shadowView.backgroundColor = .clear
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.16
        shadowView.layer.shadowRadius = 8
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 3)

        stoneContainer.clipsToBounds = true
        stoneContainer.isUserInteractionEnabled = false

        button.isUserInteractionEnabled = false
        button.clipsToBounds = true
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        badgeView.contentMode = .scaleAspectFit
        badgeView.image = UIImage(systemName: "checkmark.circle.fill")

        contentView.addSubview(haloView)
        contentView.addSubview(progressRing)
        contentView.addSubview(shadowView)
        contentView.addSubview(stoneContainer)
        stoneContainer.addSubview(button)
        stoneContainer.addSubview(thumbnailView)
        stoneContainer.addSubview(lockOverlay)
        contentView.addSubview(badgeView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        thumbnailView.isHidden = true
        lockOverlay.isHidden = true
        badgeView.isHidden = true
        haloView.isHidden = true
        progressRing.isHidden = true
        alpha = 1
    }

    func apply(lesson: PathLesson, selected: Bool, nodeSize: CGFloat) {
        currentLesson = lesson
        currentSelected = selected
        currentNodeSize = nodeSize
        let visualSize = Self.visualSize(for: lesson, nodeSize: nodeSize)
        let iconSize = LessonPathConfiguration.iconPointSize(for: visualSize)

        UIView.performWithoutAnimation {
            button.configuration = makeConfiguration(lesson: lesson, iconPointSize: iconSize)
            haloView.isHidden = !selected || lesson.state == .current
            let showProgressRing = lesson.state == .current
                && (selected || lesson.completedParts > 0)
            progressRing.isHidden = !showProgressRing
            if showProgressRing {
                progressRing.apply(
                    completedParts: lesson.completedParts,
                    partCount: LessonPathConfiguration.lessonPartCount,
                    lineWidth: LessonPathConfiguration.haloBorderWidth,
                    highlightCompleted: selected
                )
            }

            if let thumbnailName = lesson.thumbnailName, let image = UIImage(named: thumbnailName) {
                thumbnailView.isHidden = false
                thumbnailView.image = lesson.state == .locked ? Self.grayscaleImage(from: image) ?? image : image
                lockOverlay.isHidden = lesson.state != .locked
                lockOverlay.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                    pointSize: iconSize,
                    weight: .semibold
                )
            } else {
                thumbnailView.isHidden = true
                thumbnailView.image = nil
                lockOverlay.isHidden = true
            }

            let badge = max(22, visualSize * 0.34)
            let symbolSize = UIImage.SymbolConfiguration(pointSize: badge * 0.86, weight: .semibold)
            let symbolPalette = UIImage.SymbolConfiguration(
                paletteColors: [LessonPathConfiguration.burnedYellow, .systemYellow]
            )
            badgeView.preferredSymbolConfiguration = symbolSize.applying(symbolPalette)
            badgeView.isHidden = lesson.state != .completed
            alpha = lesson.state == .locked && !selected ? 0.48 : 1
        }

        accessibilityLabel = lesson.title
        isAccessibilityElement = true
        accessibilityTraits = .button
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let lesson = currentLesson else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let visualSize = Self.visualSize(for: lesson, nodeSize: currentNodeSize)
        let halo = LessonPathConfiguration.haloInset
        let origin = (bounds.width - visualSize) / 2
        let stoneFrame = CGRect(x: origin, y: origin, width: visualSize, height: visualSize)
        let iconSize = LessonPathConfiguration.iconPointSize(for: visualSize)

        stoneContainer.frame = stoneFrame
        stoneContainer.layer.cornerRadius = visualSize / 2
        button.frame = stoneContainer.bounds

        shadowView.frame = stoneFrame
        shadowView.layer.shadowPath = UIBezierPath(ovalIn: shadowView.bounds).cgPath

        haloView.frame = stoneFrame.insetBy(dx: -halo, dy: -halo)
        haloView.layer.cornerRadius = haloView.bounds.height / 2

        progressRing.frame = stoneFrame.insetBy(dx: -halo, dy: -halo)

        let photoInset = max(5, visualSize * 0.07)
        thumbnailView.frame = stoneContainer.bounds.insetBy(dx: photoInset, dy: photoInset)
        thumbnailView.layer.cornerRadius = thumbnailView.bounds.height / 2
        lockOverlay.bounds = CGRect(x: 0, y: 0, width: iconSize + 4, height: iconSize + 4)
        lockOverlay.center = CGPoint(x: stoneContainer.bounds.midX, y: stoneContainer.bounds.midY)

        let badge = max(22, visualSize * 0.34)
        badgeView.frame = CGRect(
            x: stoneFrame.maxX - badge + 4,
            y: stoneFrame.maxY - badge + 4,
            width: badge,
            height: badge
        )
    }

    private static func visualSize(for lesson: PathLesson, nodeSize: CGFloat) -> CGFloat {
        lesson.state == .locked ? nodeSize * LessonPathConfiguration.lockedScale : nodeSize
    }

    private func makeConfiguration(
        lesson: PathLesson,
        iconPointSize: CGFloat
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: iconPointSize,
            weight: .semibold
        )
        config.baseForegroundColor = lesson.state == .locked ? .secondaryLabel : .label
        config.image = lesson.thumbnailName == nil
            ? UIImage(systemName: lesson.state == .locked ? "lock.fill" : lesson.symbolName)
            : nil
        return config
    }

    private static let ciContext = CIContext()

    private static func grayscaleImage(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard
            let output = filter.outputImage,
            let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
        else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

private final class LessonPartRingView: UIView {

    private var completedParts = 0
    private var partCount = LessonPathConfiguration.lessonPartCount
    private var lineWidth: CGFloat = LessonPathConfiguration.haloBorderWidth
    private var highlightCompleted = false
    private var segmentLayers: [CAShapeLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(completedParts: Int, partCount: Int, lineWidth: CGFloat, highlightCompleted: Bool) {
        self.completedParts = completedParts
        self.partCount = max(1, partCount)
        self.lineWidth = lineWidth
        self.highlightCompleted = highlightCompleted
        rebuildSegmentsIfNeeded()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildSegmentsIfNeeded()
        let inset = lineWidth / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let visualGap: CGFloat = 3.5
        let gap = min(.pi / 8, (lineWidth + visualGap) / max(radius, 1))
        let sweep = (2 * .pi - CGFloat(partCount) * gap) / CGFloat(partCount)
        let start0 = -CGFloat.pi / 2 + gap / 2

        for (index, layer) in segmentLayers.enumerated() {
            let start = start0 + CGFloat(index) * (sweep + gap)
            let path = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: start,
                endAngle: start + sweep,
                clockwise: true
            )
            layer.path = path.cgPath
            layer.lineWidth = lineWidth
            let filled = index < completedParts
            layer.strokeColor = Self.segmentColor(
                filled: filled,
                highlighted: highlightCompleted
            ).resolvedColor(with: traitCollection).cgColor
        }
    }

    private func rebuildSegmentsIfNeeded() {
        guard segmentLayers.count != partCount else { return }
        segmentLayers.forEach { $0.removeFromSuperlayer() }
        segmentLayers = (0 ..< partCount).map { _ in
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer.addSublayer(layer)
            return layer
        }
    }

    private static func segmentColor(filled: Bool, highlighted: Bool) -> UIColor {
        if filled && highlighted {
            return UIColor.systemYellow.withAlphaComponent(0.82)
        }
        return UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            if filled {
                return (isDark ? UIColor.white : UIColor.black).withAlphaComponent(isDark ? 0.42 : 0.28)
            }
            return (isDark ? UIColor.white : UIColor.black).withAlphaComponent(isDark ? 0.18 : 0.14)
        }
    }
}

// MARK: - Lesson title tip

private final class LessonTitleTipView: UIView {

    enum ArrowEdge {
        case top
        case bottom
    }

    var onDismiss: (() -> Void)?
    var onStart: (() -> Void)?

    private static let cornerRadius: CGFloat = 26
    private static let arrowSize: CGFloat = 12
    private static let arrowProtrusion = arrowSize * CGFloat(2).squareRoot() / 2
    private static let arrowTipRadius: CGFloat = 3.6
    private static let arrowShoulderRadius: CGFloat = 2.8
    private static let cardSurface = ExperimentPalette.cardSurface

    private let bubbleLayer = CAShapeLayer()
    private let cardView = UIView()
    private let arrowView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private var arrowEdge: ArrowEdge = .top
    private var arrowXConstraint: NSLayoutConstraint?
    private var arrowTopConstraint: NSLayoutConstraint?
    private var arrowBottomConstraint: NSLayoutConstraint?
    private var cardTopConstraint: NSLayoutConstraint?
    private var cardBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        bubbleLayer.lineJoin = .round
        bubbleLayer.lineCap = .round
        bubbleLayer.lineWidth = 1.5
        layer.insertSublayer(bubbleLayer, at: 0)
        updateBubbleAppearance()

        cardView.backgroundColor = .clear
        cardView.translatesAutoresizingMaskIntoConstraints = false

        arrowView.isHidden = true
        arrowView.isUserInteractionEnabled = false
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let yellow = PrimaryButton.appearance(for: .yellow)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = yellow.backgroundColor
        config.baseForegroundColor = yellow.titleColor
        config.title = "Start Lesson"
        config.image = UIImage(systemName: "play.fill")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        startButton.configuration = config
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addAction(UIAction { [weak self] _ in
            self?.onStart?()
        }, for: .touchUpInside)

        addSubview(arrowView)
        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        cardView.addSubview(startButton)

        arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)
        arrowTopConstraint = arrowView.centerYAnchor.constraint(equalTo: cardView.topAnchor)
        arrowBottomConstraint = arrowView.centerYAnchor.constraint(equalTo: cardView.bottomAnchor)
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Self.arrowProtrusion)
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            arrowXConstraint!,
            arrowTopConstraint!,
            arrowView.widthAnchor.constraint(equalToConstant: Self.arrowSize),
            arrowView.heightAnchor.constraint(equalToConstant: Self.arrowSize),

            cardTopConstraint!,
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardBottomConstraint!,

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            startButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            startButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            startButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
            startButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = bubblePath()
        bubbleLayer.path = path.cgPath
        layer.shadowPath = path.cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBubbleAppearance()
    }

    private func updateBubbleAppearance() {
        bubbleLayer.fillColor = Self.cardSurface.resolvedColor(with: traitCollection).cgColor
        bubbleLayer.strokeColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
    }

    private func bubblePath() -> UIBezierPath {
        let card = cardView.frame
        let radius = Self.cornerRadius
        let path = UIBezierPath()
        guard card.width > radius * 2, card.height > radius * 2 else { return path }

        let baseHalf = Self.arrowProtrusion
        let minTipX = card.minX + radius + baseHalf
        let maxTipX = card.maxX - radius - baseHalf
        let tipX = min(max(arrowView.center.x, minTipX), max(minTipX, maxTipX))
        let leftBase = CGPoint(x: tipX - baseHalf, y: arrowEdge == .top ? card.minY : card.maxY)
        let rightBase = CGPoint(x: tipX + baseHalf, y: leftBase.y)
        let tip = CGPoint(
            x: tipX,
            y: arrowEdge == .top ? card.minY - baseHalf : card.maxY + baseHalf
        )
        let topLeft = CGPoint(x: card.minX + radius, y: card.minY)
        let topRight = CGPoint(x: card.maxX - radius, y: card.minY)
        let bottomLeft = CGPoint(x: card.minX + radius, y: card.maxY)

        path.move(to: topLeft)
        if arrowEdge == .top {
            addRoundedCorner(to: path, from: topLeft, corner: leftBase, to: tip, radius: Self.arrowShoulderRadius)
            addRoundedCorner(to: path, from: leftBase, corner: tip, to: rightBase, radius: Self.arrowTipRadius)
            addRoundedCorner(to: path, from: tip, corner: rightBase, to: topRight, radius: Self.arrowShoulderRadius)
            path.addLine(to: topRight)
        } else {
            path.addLine(to: topRight)
        }
        path.addArc(
            withCenter: CGPoint(x: card.maxX - radius, y: card.minY + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: card.maxX, y: card.maxY - radius))
        path.addArc(
            withCenter: CGPoint(x: card.maxX - radius, y: card.maxY - radius),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        if arrowEdge == .bottom {
            addRoundedCorner(to: path, from: CGPoint(x: card.maxX, y: card.maxY), corner: rightBase, to: tip, radius: Self.arrowShoulderRadius)
            addRoundedCorner(to: path, from: rightBase, corner: tip, to: leftBase, radius: Self.arrowTipRadius)
            addRoundedCorner(to: path, from: tip, corner: leftBase, to: bottomLeft, radius: Self.arrowShoulderRadius)
            path.addLine(to: bottomLeft)
        } else {
            path.addLine(to: bottomLeft)
        }
        path.addArc(
            withCenter: CGPoint(x: card.minX + radius, y: card.maxY - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: card.minX, y: card.minY + radius))
        path.addArc(
            withCenter: CGPoint(x: card.minX + radius, y: card.minY + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }

    private func addRoundedCorner(
        to path: UIBezierPath,
        from incoming: CGPoint,
        corner: CGPoint,
        to outgoing: CGPoint,
        radius: CGFloat
    ) {
        let v1 = CGPoint(x: incoming.x - corner.x, y: incoming.y - corner.y)
        let v2 = CGPoint(x: outgoing.x - corner.x, y: outgoing.y - corner.y)
        let length1 = hypot(v1.x, v1.y)
        let length2 = hypot(v2.x, v2.y)
        guard length1 > 0.5, length2 > 0.5, radius > 0 else {
            path.addLine(to: corner)
            return
        }

        let n1 = CGPoint(x: v1.x / length1, y: v1.y / length1)
        let n2 = CGPoint(x: v2.x / length2, y: v2.y / length2)
        let cross = n1.x * n2.y - n1.y * n2.x
        let dot = max(-1, min(1, n1.x * n2.x + n1.y * n2.y))
        let angle = atan2(cross, dot)
        let halfAngle = abs(angle) / 2
        guard halfAngle > 0.02 else {
            path.addLine(to: corner)
            return
        }

        let inset = min(radius / tan(halfAngle), length1 * 0.42, length2 * 0.42)
        let start = CGPoint(x: corner.x + n1.x * inset, y: corner.y + n1.y * inset)
        let end = CGPoint(x: corner.x + n2.x * inset, y: corner.y + n2.y * inset)
        let centerDistance = inset / cos(halfAngle)
        let bisector = CGPoint(x: n1.x + n2.x, y: n1.y + n2.y)
        let bisectorLength = hypot(bisector.x, bisector.y)
        guard bisectorLength > 0.01 else {
            path.addLine(to: corner)
            return
        }

        let center = CGPoint(
            x: corner.x + bisector.x / bisectorLength * centerDistance,
            y: corner.y + bisector.y / bisectorLength * centerDistance
        )
        path.addLine(to: start)
        path.addArc(
            withCenter: center,
            radius: hypot(start.x - center.x, start.y - center.y),
            startAngle: atan2(start.y - center.y, start.x - center.x),
            endAngle: atan2(end.y - center.y, end.x - center.x),
            clockwise: angle < 0
        )
    }

    func apply(title: String, subtitle: String, hasProgress: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        startButton.configuration?.title = hasProgress ? "Continue Lesson" : "Start Lesson"
        invalidateIntrinsicContentSize()
    }

    func setArrowEdge(_ edge: ArrowEdge) {
        arrowEdge = edge
        switch edge {
        case .top:
            arrowTopConstraint?.isActive = true
            arrowBottomConstraint?.isActive = false
            cardTopConstraint?.constant = Self.arrowProtrusion
            cardBottomConstraint?.constant = 0
        case .bottom:
            arrowTopConstraint?.isActive = false
            arrowBottomConstraint?.isActive = true
            cardTopConstraint?.constant = 0
            cardBottomConstraint?.constant = -Self.arrowProtrusion
        }
        setNeedsLayout()
    }

    func setSourceCenterX(_ sourceCenterX: CGFloat) {
        let offset = sourceCenterX - frame.midX
        let maxOffset = bounds.width * 0.38
        arrowXConstraint?.constant = max(-maxOffset, min(maxOffset, offset))
    }

    func showWithAnimation() {
        transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        alpha = 0
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: .curveEaseOut) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    func dismissWithAnimation(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            self.alpha = 0
        } completion: { _ in
            completion?()
        }
    }
}

// MARK: - Tuning sheet

private final class LessonPathTuningSheetViewController: UIViewController {

    var onChange: ((LessonPathConfiguration) -> Void)?
    var onReset: (() -> Void)?

    private var configuration: LessonPathConfiguration
    private let sliderStack = UIStackView()
    private var sliderRows: [(spec: PathTuningSliderSpec, slider: UISlider, valueLabel: UILabel)] = []

    init(configuration: LessonPathConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Tune path"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = UIButton(type: .system)
        resetButton.configuration = makeHeaderButtonConfiguration(title: "Reset")
        resetButton.addAction(UIAction { [weak self] _ in
            self?.onReset?()
        }, for: .touchUpInside)

        let copyButton = UIButton(type: .system)
        copyButton.configuration = makeHeaderButtonConfiguration(title: "Copy")
        copyButton.addAction(UIAction { [weak self] _ in
            self?.copyRecipe()
        }, for: .touchUpInside)

        let headerButtons = UIStackView(arrangedSubviews: [resetButton, copyButton])
        headerButtons.axis = .horizontal
        headerButtons.spacing = 8
        headerButtons.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        header.addSubview(headerButtons)

        sliderStack.axis = .vertical
        sliderStack.spacing = 16
        sliderStack.translatesAutoresizingMaskIntoConstraints = false

        for spec in PathTuningSliderSpec.allCases {
            let row = makeSliderRow(for: spec)
            sliderRows.append((spec, row.slider, row.valueLabel))
            sliderStack.addArrangedSubview(row.container)
        }

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(sliderStack)

        view.addSubview(header)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            header.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            headerButtons.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerButtons.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerButtons.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sliderStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            sliderStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            sliderStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            sliderStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            sliderStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        syncSlidersFromConfiguration()
    }

    func sync(configuration: LessonPathConfiguration) {
        self.configuration = configuration
        syncSlidersFromConfiguration()
    }

    private func makeHeaderButtonConfiguration(title: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.baseForegroundColor = .systemBlue
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        return config
    }

    private func makeSliderRow(for spec: PathTuningSliderSpec) -> (container: UIView, slider: UISlider, valueLabel: UILabel) {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.text = spec.title

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = spec.range.lowerBound
        slider.maximumValue = spec.range.upperBound
        slider.minimumTrackTintColor = .systemYellow
        slider.maximumTrackTintColor = .tertiarySystemFill
        slider.addAction(UIAction { [weak self] action in
            guard let self, let slider = action.sender as? UISlider else { return }
            let stepped = Self.steppedValue(slider.value, step: spec.step, range: spec.range)
            slider.value = stepped
            self.write(spec, value: stepped)
        }, for: .valueChanged)

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            slider.heightAnchor.constraint(equalToConstant: 28),
        ])

        return (container, slider, valueLabel)
    }

    private func write(_ spec: PathTuningSliderSpec, value: Float) {
        switch spec {
        case .spacing: configuration.spacing = CGFloat(value)
        case .frequency: configuration.frequency = CGFloat(value)
        case .amplitude: configuration.amplitude = CGFloat(value)
        case .nodeSize: configuration.nodeSize = CGFloat(value)
        case .phase: configuration.phase = CGFloat(value)
        }
        updateValueLabel(for: spec)
        onChange?(configuration)
    }

    private func syncSlidersFromConfiguration() {
        for row in sliderRows {
            row.slider.value = read(row.spec)
            updateValueLabel(for: row.spec)
        }
    }

    private func updateValueLabel(for spec: PathTuningSliderSpec) {
        guard let row = sliderRows.first(where: { $0.spec == spec }) else { return }
        row.valueLabel.text = formattedValue(read(spec), spec: spec)
    }

    private func read(_ spec: PathTuningSliderSpec) -> Float {
        switch spec {
        case .spacing: return Float(configuration.spacing)
        case .frequency: return Float(configuration.frequency)
        case .amplitude: return Float(configuration.amplitude)
        case .nodeSize: return Float(configuration.nodeSize)
        case .phase: return Float(configuration.phase)
        }
    }

    private func formattedValue(_ value: Float, spec: PathTuningSliderSpec) -> String {
        switch spec {
        case .spacing, .nodeSize:
            return String(format: "%.0f", value)
        case .frequency, .amplitude, .phase:
            return String(format: "%.2f", value)
        }
    }

    private func copyRecipe() {
        let text = """
        spacing: \(formattedValue(Float(configuration.spacing), spec: .spacing))
        frequency: \(formattedValue(Float(configuration.frequency), spec: .frequency))
        amplitude: \(formattedValue(Float(configuration.amplitude), spec: .amplitude))
        nodeSize: \(formattedValue(Float(configuration.nodeSize), spec: .nodeSize))
        phase: \(formattedValue(Float(configuration.phase), spec: .phase))
        """
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static func steppedValue(_ value: Float, step: Float, range: ClosedRange<Float>) -> Float {
        let stepped = (value / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
