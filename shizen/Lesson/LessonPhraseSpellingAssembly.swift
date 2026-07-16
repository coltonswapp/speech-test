//
//  LessonPhraseSpellingAssembly.swift
//  shizen
//
//  Kana-spelling-style phrase assembly: tiles fly from a bank into an ordered row.
//

import UIKit

private enum LessonPhraseSpellingMotion {
    static let settleDuration: TimeInterval = 0.08
    static let slideDuration: TimeInterval = 0.18
    static let flightDuration: TimeInterval = 0.17
    static let flightTiming = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.25, y: 1),
        controlPoint2: CGPoint(x: 0.35, y: 1)
    )
    static let highlightDuration: TimeInterval = 0.18
    static let landingHighlightDuration: TimeInterval = 0.11
    static let landingSettleDuration: TimeInterval = 0.06
    static let successCheckDelay: TimeInterval = 0.22
    static let successCascadeStagger: TimeInterval = 0.09
    static let snapDuration: TimeInterval = 0.14
    static let spellingTwoTileChimeLead: TimeInterval = 0.04

    static func successChimeKeyTime(forSyllableCount count: Int) -> TimeInterval {
        KanaSoundMatchMetrics.successChimeKeyTime
    }

    static func successChimeLead(forSyllableCount count: Int) -> TimeInterval {
        count == 2 ? spellingTwoTileChimeLead : 0
    }
    static let pressScale: CGFloat = 0.94
    static let pressDownDuration: TimeInterval = 0.075
    static let pressUpDuration: TimeInterval = 0.12
    static let pressUpDamping: CGFloat = 0.72
    static let incorrectShakeDuration: TimeInterval = 0.42
    static let incorrectShakeDisplacement: CGFloat = 10
    static let returnRowShiftDelay: TimeInterval = 0.06
    static let returnSlideDuration: TimeInterval = 0.14
    static let arrivalSettleScale: CGFloat = 0.96
    static let landingSettleDamping: CGFloat = 0.82
    static let landingSettleVelocity: CGFloat = 0.55
}

private final class LessonPhraseTile: UIControl {

    enum Highlight {
        case normal
        case selected
        case correct
    }

    let phrase: String
    var homeGridIndex: Int?
    private let phraseLabel = UILabel()
    private var currentHighlight: Highlight = .normal
    private var isPressScaled = false

    let tileWidth: CGFloat
    static let tileHeight: CGFloat = 78
    private static let horizontalPadding: CGFloat = 14
    private static let phraseFont = UIFont.systemFont(ofSize: 22, weight: .semibold)

    init(phrase: String) {
        self.phrase = phrase
        let textWidth = (phrase as NSString).size(withAttributes: [.font: Self.phraseFont]).width
        tileWidth = max(56, ceil(textWidth) + Self.horizontalPadding * 2)
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
            withDuration: LessonPhraseSpellingMotion.highlightDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            apply()
        }
    }

    func animateLandingSelection(completion: (() -> Void)? = nil) {
        isPressScaled = false
        layer.removeAllAnimations()
        let selected = appearance(for: .selected)
        currentHighlight = .selected
        applyAppearance(appearance(for: .normal))
        transform = CGAffineTransform(
            scaleX: LessonPhraseSpellingMotion.arrivalSettleScale,
            y: LessonPhraseSpellingMotion.arrivalSettleScale
        )
        layer.borderColor = selected.borderColor?.resolvedColor(with: traitCollection).cgColor

        UIView.animate(
            withDuration: LessonPhraseSpellingMotion.landingHighlightDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.backgroundColor = selected.backgroundColor
            self.layer.borderWidth = selected.borderWidth
        }

        UIView.animate(
            withDuration: LessonPhraseSpellingMotion.landingSettleDuration,
            delay: 0,
            usingSpringWithDamping: LessonPhraseSpellingMotion.landingSettleDamping,
            initialSpringVelocity: LessonPhraseSpellingMotion.landingSettleVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        } completion: { _ in
            completion?()
        }
    }

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
                backgroundColor: ExperimentPalette.cardSurface,
                borderWidth: ExperimentCardStroke.normalWidth,
                borderColor: ExperimentPalette.cardBorder
            )
        case .selected:
            TileAppearance(
                backgroundColor: ExperimentPalette.highlightFill,
                borderWidth: ExperimentCardStroke.emphasisWidth,
                borderColor: ExperimentPalette.highlightBorder
            )
        case .correct:
            TileAppearance(
                backgroundColor: ExperimentPalette.successFill,
                borderWidth: ExperimentCardStroke.emphasisWidth,
                borderColor: ExperimentPalette.successBorder
            )
        }
    }

    private func applyAppearance(_ appearance: TileAppearance) {
        backgroundColor = appearance.backgroundColor
        layer.borderWidth = appearance.borderWidth
        layer.borderColor = appearance.borderColor?
            .resolvedColor(with: traitCollection).cgColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = ExperimentCardStroke.choiceCornerRadius
        layer.cornerCurve = .continuous
        applyAppearance(appearance(for: .normal))

        phraseLabel.text = phrase
        phraseLabel.font = Self.phraseFont
        phraseLabel.textAlignment = .center
        phraseLabel.numberOfLines = 1
        phraseLabel.textColor = .label
        phraseLabel.isUserInteractionEnabled = false
        phraseLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(phraseLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: tileWidth),
            heightAnchor.constraint(equalToConstant: Self.tileHeight),
            phraseLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            phraseLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            phraseLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.horizontalPadding),
            phraseLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.horizontalPadding),
        ])

        setupPressHandling()
    }

    private func setupPressHandling() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchDragExit), for: .touchDragExit)
        addTarget(self, action: #selector(touchUpOutside), for: .touchUpOutside)
        addTarget(self, action: #selector(touchCancel), for: .touchCancel)
        addTarget(self, action: #selector(touchUpInside), for: .touchUpInside)
    }

    @objc private func touchDown() {
        guard isEnabled, currentHighlight != .correct else { return }
        ExperimentFeedbackSound.playClick()
        UIView.animate(withDuration: LessonPhraseSpellingMotion.pressDownDuration, delay: 0, options: [.allowUserInteraction]) {
            self.transform = CGAffineTransform(
                scaleX: LessonPhraseSpellingMotion.pressScale,
                y: LessonPhraseSpellingMotion.pressScale
            )
        }
        isPressScaled = true
    }

    @objc private func touchDragExit() { resetPressAnimation() }
    @objc private func touchUpOutside() { resetPressAnimation() }
    @objc private func touchCancel() { resetPressAnimation() }
    @objc private func touchUpInside() { resetPressAnimation() }

    private func resetPressAnimation() {
        guard isPressScaled else { return }
        isPressScaled = false
        UIView.animate(
            withDuration: LessonPhraseSpellingMotion.pressUpDuration,
            delay: 0,
            usingSpringWithDamping: LessonPhraseSpellingMotion.pressUpDamping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.transform = .identity
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance(appearance(for: currentHighlight))
    }

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
}

/// Phrase bank + spelling row patterned after `KanaSpellingViewController`.
final class LessonPhraseSpellingAssemblyView: UIView {

    var onSelectionChanged: (() -> Void)?

    private static let slotSpacing: CGFloat = 8
    private static let gridSpacing: CGFloat = 11
    private static let spellingLineHorizontalPadding: CGFloat = 24
    private static let spellingRowToLineSpacing: CGFloat = 10
    private static let gridColumns = 2

    private let spellingRowWrapper = UIView()
    private let spellingLineWrapper = UIView()
    private let spellingLine = UIView()
    private let spellingRowContainer = UIView()
    private let spellingStack = UIStackView()
    private let gridStack = UIStackView()

    private var slotCount = 0
    private var spellingSlots: [UIView] = []
    private var spellingSlotTiles: [LessonPhraseTile?] = []
    private var slotWidthConstraints: [NSLayoutConstraint?] = []
    private var gridRowStacks: [UIStackView] = []
    private var gridPlaceholders: [Int: UIView] = [:]
    private var tilesReturningToGrid = Set<ObjectIdentifier>()
    private var returningSpellingSlotIndices = Set<Int>()
    private var pendingReturnRemovalIndices = Set<Int>()
    private var returnLayoutWorkItem: DispatchWorkItem?
    private var hasSucceeded = false
    private var successCascadeGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureChrome()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureChrome()
    }

    var selectedPhrases: [String] {
        spellingSlotTiles.compactMap { $0?.phrase }
    }

    var isFull: Bool {
        spellingSlotTiles.compactMap { $0 }.count >= slotCount
    }

    func configure(choices: [String], slotCount: Int) {
        resetState()
        self.slotCount = max(slotCount, 1)
        rebuildSpellingSlots()
        rebuildGrid(choices: choices.shuffled())
        syncSpellingSlotVisibility()
    }

    func playIncorrectShake() {
        let views: [UIView] = [spellingRowContainer, gridStack]
        let displacement = LessonPhraseSpellingMotion.incorrectShakeDisplacement
        for view in views {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.duration = LessonPhraseSpellingMotion.incorrectShakeDuration
            animation.values = [0, -displacement, displacement, -displacement * 0.72, displacement * 0.72, 0]
            view.layer.add(animation, forKey: "phraseSpelling.shake")
        }
    }

    func playSuccess(completion: @escaping () -> Void) {
        hasSucceeded = true
        let tiles = spellingSlotTiles.compactMap { $0 }
        successCascadeGeneration += 1
        let generation = successCascadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + LessonPhraseSpellingMotion.successCheckDelay) { [weak self] in
            guard let self, generation == self.successCascadeGeneration, self.hasSucceeded else { return }
            let successSound = ExperimentFeedbackSound.prepareSuccess(
                for: .kanaSpelling,
                spellingSyllableCount: tiles.count
            )
            self.playSuccessCascade(tiles: tiles, successSound: successSound, completion: completion)
        }
    }

    func setInteractionEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        for tile in allTiles() {
            tile.isUserInteractionEnabled = enabled && !hasSucceeded
        }
    }

    private func allTiles() -> [LessonPhraseTile] {
        var tiles: [LessonPhraseTile] = []
        for row in gridRowStacks {
            for case let tile as LessonPhraseTile in row.arrangedSubviews {
                tiles.append(tile)
            }
        }
        tiles.append(contentsOf: spellingSlotTiles.compactMap { $0 })
        return tiles
    }

    private func configureChrome() {
        translatesAutoresizingMaskIntoConstraints = false

        spellingLine.backgroundColor = ExperimentPalette.prominentSeparator
        spellingLine.translatesAutoresizingMaskIntoConstraints = false

        spellingStack.axis = .horizontal
        spellingStack.alignment = .center
        spellingStack.distribution = .fill
        spellingStack.spacing = Self.slotSpacing

        spellingRowContainer.translatesAutoresizingMaskIntoConstraints = false
        spellingStack.translatesAutoresizingMaskIntoConstraints = false
        spellingRowContainer.addSubview(spellingStack)

        spellingRowWrapper.translatesAutoresizingMaskIntoConstraints = false
        spellingRowWrapper.addSubview(spellingRowContainer)

        spellingLineWrapper.translatesAutoresizingMaskIntoConstraints = false
        spellingLineWrapper.addSubview(spellingLine)

        gridStack.axis = .vertical
        gridStack.alignment = .center
        gridStack.spacing = Self.gridSpacing
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        let spellingArea = UIStackView(arrangedSubviews: [spellingRowWrapper, spellingLineWrapper])
        spellingArea.axis = .vertical
        spellingArea.alignment = .center
        spellingArea.spacing = Self.spellingRowToLineSpacing
        spellingArea.translatesAutoresizingMaskIntoConstraints = false

        let root = UIStackView(arrangedSubviews: [spellingArea, gridStack])
        root.axis = .vertical
        root.alignment = .fill
        root.spacing = 28
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),

            spellingRowWrapper.heightAnchor.constraint(equalToConstant: LessonPhraseTile.tileHeight),
            spellingRowWrapper.leadingAnchor.constraint(equalTo: spellingArea.leadingAnchor),
            spellingRowWrapper.trailingAnchor.constraint(equalTo: spellingArea.trailingAnchor),

            spellingRowContainer.centerXAnchor.constraint(equalTo: spellingRowWrapper.centerXAnchor),
            spellingRowContainer.topAnchor.constraint(equalTo: spellingRowWrapper.topAnchor),
            spellingRowContainer.bottomAnchor.constraint(equalTo: spellingRowWrapper.bottomAnchor),
            spellingRowContainer.heightAnchor.constraint(equalToConstant: LessonPhraseTile.tileHeight),
            spellingRowContainer.widthAnchor.constraint(equalTo: spellingStack.widthAnchor),

            spellingStack.leadingAnchor.constraint(equalTo: spellingRowContainer.leadingAnchor),
            spellingStack.topAnchor.constraint(equalTo: spellingRowContainer.topAnchor),
            spellingStack.bottomAnchor.constraint(equalTo: spellingRowContainer.bottomAnchor),
            spellingStack.trailingAnchor.constraint(equalTo: spellingRowContainer.trailingAnchor),

            spellingLine.topAnchor.constraint(equalTo: spellingLineWrapper.topAnchor),
            spellingLine.bottomAnchor.constraint(equalTo: spellingLineWrapper.bottomAnchor),
            spellingLine.heightAnchor.constraint(equalToConstant: 1),
            spellingLine.leadingAnchor.constraint(equalTo: spellingLineWrapper.leadingAnchor, constant: Self.spellingLineHorizontalPadding),
            spellingLine.trailingAnchor.constraint(equalTo: spellingLineWrapper.trailingAnchor, constant: -Self.spellingLineHorizontalPadding),
            spellingLineWrapper.leadingAnchor.constraint(equalTo: spellingArea.leadingAnchor),
            spellingLineWrapper.trailingAnchor.constraint(equalTo: spellingArea.trailingAnchor),
        ])
    }

    private func resetState() {
        returnLayoutWorkItem?.cancel()
        returnLayoutWorkItem = nil
        hasSucceeded = false
        successCascadeGeneration += 1
        tilesReturningToGrid.removeAll()
        returningSpellingSlotIndices.removeAll()
        pendingReturnRemovalIndices.removeAll()
        gridPlaceholders.removeAll()

        for tile in spellingSlotTiles.compactMap({ $0 }) {
            tile.removeFromSuperview()
        }
        spellingSlotTiles.removeAll()
        spellingSlots.removeAll()
        slotWidthConstraints.removeAll()
        spellingStack.arrangedSubviews.forEach {
            spellingStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for row in gridRowStacks {
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        gridRowStacks.removeAll()
    }

    private func rebuildSpellingSlots() {
        spellingSlotTiles = Array(repeating: nil, count: slotCount)
        slotWidthConstraints = Array(repeating: nil, count: slotCount)
        for _ in 0 ..< slotCount {
            let slot = makeSlotView()
            slot.isHidden = true
            spellingStack.addArrangedSubview(slot)
            spellingSlots.append(slot)
        }
    }

    private func applySlotWidth(at index: Int, width: CGFloat) {
        guard spellingSlots.indices.contains(index) else { return }
        if let existing = slotWidthConstraints[index] {
            existing.isActive = false
        }
        let constraint = spellingSlots[index].widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        slotWidthConstraints[index] = constraint
    }

    private func clearSlotWidth(at index: Int) {
        guard spellingSlots.indices.contains(index) else { return }
        slotWidthConstraints[index]?.isActive = false
        slotWidthConstraints[index] = nil
    }

    private func rebuildGrid(choices: [String]) {
        let rows = Int(ceil(Double(choices.count) / Double(Self.gridColumns)))
        for _ in 0 ..< rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.distribution = .fill
            row.spacing = Self.gridSpacing
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: LessonPhraseTile.tileHeight).isActive = true
            gridRowStacks.append(row)
            gridStack.addArrangedSubview(row)
        }

        for (index, phrase) in choices.enumerated() {
            let tile = LessonPhraseTile(phrase: phrase)
            tile.homeGridIndex = index
            tile.addTarget(self, action: #selector(gridTileTapped(_:)), for: .touchUpInside)
            let row = index / Self.gridColumns
            let column = index % Self.gridColumns
            gridRowStacks[row].insertArrangedSubview(tile, at: column)
        }
    }

    private func makeSlotView() -> UIView {
        let slot = UIView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.heightAnchor.constraint(equalToConstant: LessonPhraseTile.tileHeight).isActive = true
        return slot
    }

    private func makeGridPlaceholder(size: CGSize) -> UIView {
        let gap = UIView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            gap.widthAnchor.constraint(equalToConstant: size.width),
            gap.heightAnchor.constraint(equalToConstant: size.height),
        ])
        return gap
    }

    @objc private func gridTileTapped(_ sender: UIControl) {
        guard !hasSucceeded, let tile = sender as? LessonPhraseTile else { return }
        guard isTileInGrid(tile), let slotIndex = nextSpellingSlotIndex() else { return }

        tile.cancelPressFeedback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let slot = spellingSlots[slotIndex]
        let previousCount = spellingSlotTiles.compactMap { $0 }.count
        let existingTiles = spellingSlotTiles[0 ..< previousCount].compactMap { $0 }

        spellingSlotTiles[slotIndex] = tile
        applySlotWidth(at: slotIndex, width: tile.tileWidth)

        animateSpellingRelayout(tiles: existingTiles, duration: LessonPhraseSpellingMotion.slideDuration) { [weak self] in
            self?.syncSpellingSlotVisibility()
        }

        wireSpellingTap(tile)
        animateFromGrid(tile: tile, to: slot, slotIndex: slotIndex)
        onSelectionChanged?()
    }

    @objc private func spellingTileTapped(_ sender: UIControl) {
        guard !hasSucceeded, let tile = sender as? LessonPhraseTile else { return }
        let tileID = ObjectIdentifier(tile)
        guard !tilesReturningToGrid.contains(tileID) else { return }
        guard let spellingIndex = spellingSlotTiles.firstIndex(where: { $0 === tile }),
              let homeIndex = tile.homeGridIndex,
              let window = window else { return }

        tile.cancelPressFeedback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let previousCount = spellingSlotTiles.compactMap { $0 }.count
        let newCount = previousCount - 1

        tilesReturningToGrid.insert(tileID)
        returningSpellingSlotIndices.insert(spellingIndex)
        spellingSlotTiles[spellingIndex] = nil
        tile.setHighlight(.normal)
        applySlotWidth(at: spellingIndex, width: tile.tileWidth)
        syncSpellingSlotVisibility()

        layoutIfNeeded()
        let startFrame = tile.convert(tile.bounds, to: window)
        let placeholder = prepareGridPlaceholder(at: homeIndex, tileSize: tile.bounds.size)
        layoutIfNeeded()
        let landingFrame = tileFrame(in: placeholder, size: tile.bounds.size, relativeTo: window)

        spellingSlots[spellingIndex].subviews.forEach { $0.removeFromSuperview() }

        if newCount > 0 {
            scheduleSpellingReturnLayout(removingAt: spellingIndex)
        }

        animateReturnToGrid(
            tile: tile,
            spellingSlotIndex: spellingIndex,
            landingFrame: landingFrame,
            startFrame: startFrame
        ) { [weak self] in
            guard let self else { return }
            self.tilesReturningToGrid.remove(tileID)
            self.returningSpellingSlotIndices.remove(spellingIndex)
            if newCount == 0 {
                self.applySpellingRowLayoutWithoutAnimation()
            }
            self.onSelectionChanged?()
        }
    }

    private func wireSpellingTap(_ tile: LessonPhraseTile) {
        tile.removeTarget(self, action: #selector(gridTileTapped(_:)), for: .touchUpInside)
        tile.addTarget(self, action: #selector(spellingTileTapped(_:)), for: .touchUpInside)
    }

    private func wireGridTap(_ tile: LessonPhraseTile) {
        tile.removeTarget(self, action: #selector(spellingTileTapped(_:)), for: .touchUpInside)
        tile.addTarget(self, action: #selector(gridTileTapped(_:)), for: .touchUpInside)
    }

    private func isTileInGrid(_ tile: LessonPhraseTile) -> Bool {
        guard let index = tile.homeGridIndex else { return false }
        return gridPlaceholders[index] == nil && !spellingSlotTiles.contains(where: { $0 === tile })
    }

    private func nextSpellingSlotIndex() -> Int? {
        spellingSlotTiles.firstIndex(where: { $0 == nil })
    }

    private func rowAndColumn(forGridIndex index: Int) -> (row: Int, column: Int) {
        (index / Self.gridColumns, index % Self.gridColumns)
    }

    private func prepareGridPlaceholder(at gridIndex: Int, tileSize: CGSize) -> UIView {
        let (row, column) = rowAndColumn(forGridIndex: gridIndex)
        let rowStack = gridRowStacks[row]
        if let existing = gridPlaceholders[gridIndex] {
            return existing
        }
        let placeholder = makeGridPlaceholder(size: tileSize)
        rowStack.insertArrangedSubview(placeholder, at: column)
        gridPlaceholders[gridIndex] = placeholder
        return placeholder
    }

    private func removeTileFromGrid(_ tile: LessonPhraseTile) {
        guard let index = tile.homeGridIndex else { return }
        let (row, column) = rowAndColumn(forGridIndex: index)
        let rowStack = gridRowStacks[row]
        if gridPlaceholders[index] == nil {
            let placeholder = makeGridPlaceholder(size: tile.bounds.size)
            rowStack.insertArrangedSubview(placeholder, at: column)
            gridPlaceholders[index] = placeholder
        }
        rowStack.removeArrangedSubview(tile)
        tile.removeFromSuperview()
    }

    private func insertTileInGrid(_ tile: LessonPhraseTile) {
        guard let index = tile.homeGridIndex else { return }
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

    private func embed(tile: LessonPhraseTile, in slot: UIView, at index: Int) {
        tile.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(tile)
        applySlotWidth(at: index, width: tile.tileWidth)
        NSLayoutConstraint.activate([
            tile.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            tile.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])
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
                if slot.isHidden {
                    clearSlotWidth(at: index)
                }
            }
        }
    }

    private func applySpellingRowLayoutWithoutAnimation() {
        syncSpellingSlotVisibility()
        UIView.performWithoutAnimation {
            spellingRowContainer.layoutIfNeeded()
        }
    }

    private func scheduleSpellingReturnLayout(removingAt spellingIndex: Int) {
        pendingReturnRemovalIndices.insert(spellingIndex)
        returnLayoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyPendingReturnLayouts()
        }
        returnLayoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LessonPhraseSpellingMotion.returnRowShiftDelay,
            execute: work
        )
    }

    private func applyPendingReturnLayouts() {
        returnLayoutWorkItem = nil
        let removedIndices = pendingReturnRemovalIndices
        pendingReturnRemovalIndices.removeAll()
        returningSpellingSlotIndices.subtract(removedIndices)
        for index in removedIndices {
            spellingSlotTiles[index] = nil
            clearSlotWidth(at: index)
        }
        syncSpellingSlotVisibility()
        let remaining = spellingSlotTiles.compactMap { $0 }
        guard !remaining.isEmpty else {
            applySpellingRowLayoutWithoutAnimation()
            return
        }
        var compacted = Array(repeating: nil as LessonPhraseTile?, count: slotCount)
        for (index, tile) in remaining.enumerated() {
            compacted[index] = tile
        }
        animateSpellingRelayout(tiles: remaining, duration: LessonPhraseSpellingMotion.returnSlideDuration) { [weak self] in
            guard let self else { return }
            self.spellingSlotTiles = compacted
            for index in self.spellingSlots.indices {
                self.spellingSlots[index].subviews.forEach { $0.removeFromSuperview() }
                self.clearSlotWidth(at: index)
            }
            self.syncSpellingSlotVisibility()
            for (index, tile) in remaining.enumerated() {
                self.embed(tile: tile, in: self.spellingSlots[index], at: index)
                self.wireSpellingTap(tile)
            }
            self.applySpellingRowLayoutWithoutAnimation()
        }
    }

    private func animateSpellingRelayout(
        tiles: [LessonPhraseTile],
        duration: TimeInterval,
        updates: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard let window = self.window else {
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
            spellingRowContainer.layoutIfNeeded()
        }

        var movedTiles: [LessonPhraseTile] = []
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

        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            movedTiles.forEach { $0.transform = .identity }
        } completion: { _ in
            completion?()
        }
    }

    private func tileFrame(in container: UIView, size: CGSize, relativeTo coordinateView: UIView) -> CGRect {
        layoutIfNeeded()
        let originInContainer = CGPoint(
            x: (container.bounds.width - size.width) / 2,
            y: (container.bounds.height - size.height) / 2
        )
        return CGRect(origin: container.convert(originInContainer, to: coordinateView), size: size)
    }

    private func makeFlyer(from tile: LessonPhraseTile) -> UIView? {
        tile.snapshotView(afterScreenUpdates: true)
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
            duration: LessonPhraseSpellingMotion.flightDuration,
            timingParameters: LessonPhraseSpellingMotion.flightTiming
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

    private func animateFromGrid(tile: LessonPhraseTile, to slot: UIView, slotIndex: Int) {
        guard let window = window else {
            removeTileFromGrid(tile)
            embed(tile: tile, in: slot, at: slotIndex)
            tile.animateLandingSelection()
            return
        }

        layoutIfNeeded()
        tile.cancelPressFeedback()
        let startFrame = tile.convert(tile.bounds, to: window)
        let endFrame = tileFrame(in: slot, size: tile.bounds.size, relativeTo: window)

        guard let flyer = makeFlyer(from: tile) else {
            removeTileFromGrid(tile)
            embed(tile: tile, in: slot, at: slotIndex)
            tile.animateLandingSelection()
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
            guard let self else { return }
            flyer.removeFromSuperview()
            tile.isHidden = false
            tile.transform = .identity
            self.embed(tile: tile, in: slot, at: slotIndex)
            self.wireSpellingTap(tile)
            tile.animateLandingSelection()
        }
    }

    private func animateReturnToGrid(
        tile: LessonPhraseTile,
        spellingSlotIndex: Int,
        landingFrame: CGRect,
        startFrame: CGRect,
        completion: @escaping () -> Void
    ) {
        guard let window = window else {
            insertTileInGrid(tile)
            completion()
            return
        }

        tile.isHidden = true
        guard let flyer = makeFlyer(from: tile) else {
            insertTileInGrid(tile)
            completion()
            return
        }

        animateFlight(
            flyer: flyer,
            from: startFrame,
            to: CGPoint(x: landingFrame.midX, y: landingFrame.midY),
            in: window
        ) { [weak self] in
            flyer.removeFromSuperview()
            tile.isHidden = false
            tile.transform = .identity
            tile.setHighlight(.normal)
            self?.insertTileInGrid(tile)
            UIView.animate(withDuration: LessonPhraseSpellingMotion.settleDuration) {
                tile.transform = .identity
            } completion: { _ in
                completion()
            }
        }
    }

    private func playSuccessCascade(
        tiles: [LessonPhraseTile],
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

        let stagger = LessonPhraseSpellingMotion.successCascadeStagger
        let chimeKeyTime = LessonPhraseSpellingMotion.successChimeKeyTime(forSyllableCount: count)
        let chimeLead = LessonPhraseSpellingMotion.successChimeLead(forSyllableCount: count)

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
