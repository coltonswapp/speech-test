//
//  HiraganaChartViews.swift
//  shizen
//
//  Hiragana grids (seion, dakuten, yōon) for HiraganaChartViewController (DEBUG).
//


import UIKit

private enum HiraganaChartMetrics {
    /// Tracks row labels (`k-`, …) and aligns the header spacer with that column.
    static let prefixColumnWidth: CGFloat = 18
    /// Space between prefix column and the five kana tiles (also below `-a`/… headers).
    static let prefixToGridSpacing: CGFloat = 14
    /// Matches `KanaCard` geometry so textbook gaps occupy the same cell bounds without chrome.
    static let kanaTileAspectHeightOverWidth: CGFloat = 1.28
    static let progressTrackHeight: CGFloat = 6
}

// MARK: - KanaCard

enum KanaCardAccess: Equatable {
    case reference
    case locked
    case learning(studyCount: Int)
}

final class KanaCard: UIView {

    enum Presentation {
        case grid
        case detailHero
    }

    private let kanaLabel = UILabel()
    private let romajiLabel = UILabel()
    private let stack = UIStackView()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var presentation: Presentation = .grid
    private var access: KanaCardAccess = .reference
    private var heightConstraint: NSLayoutConstraint?
    private var stackCenterYConstraint: NSLayoutConstraint?
    private var progressFillWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    var onTap: (() -> Void)? {
        didSet { updateTapGesture() }
    }

    var kana: String? { storedKana }
    var romaji: String? { storedRomaji }

    var isLockedForInteraction: Bool {
        if case .locked = access { return true }
        return false
    }

    var isChartSelected = false {
        didSet {
            guard oldValue != isChartSelected else { return }
            applySelectionChrome()
            updateTapGesture()
        }
    }

    var isChartSelectionEnabled = false {
        didSet {
            guard oldValue != isChartSelectionEnabled else { return }
            updateTapGesture()
        }
    }

    private var storedKana: String?
    private var storedRomaji: String?
    private lazy var tapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        addGestureRecognizer(tap)
        return tap
    }()

    func setPresentation(_ presentation: Presentation) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation
        updateHeightAspect()
        applyTypography()
        configureAppearance()
        if case .learning(let studyCount) = access {
            updateProgressBar(studyCount: studyCount)
        } else {
            updateProgressBar(studyCount: 0)
        }
    }

    func setAccess(_ access: KanaCardAccess) {
        guard self.access != access else { return }
        self.access = access
        if access == .locked {
            isChartSelected = false
            isChartSelectionEnabled = false
        }
        applyAccessAppearance()
        updateTapGesture()
    }

    private func updateHeightAspect() {
        heightConstraint?.isActive = false
        let multiplier: CGFloat = presentation == .detailHero
            ? 1.24
            : HiraganaChartMetrics.kanaTileAspectHeightOverWidth
        let height = heightAnchor.constraint(equalTo: widthAnchor, multiplier: multiplier)
        heightConstraint = height
        height.isActive = true
    }

    func configure(kana: String?, romaji: String?) {
        storedKana = kana
        storedRomaji = romaji
        let hasKana = !(kana?.isEmpty ?? true)
        let hasRomaji = !(romaji?.isEmpty ?? true)
        kanaLabel.text = kana
        romajiLabel.text = access == .locked ? nil : romaji
        applyAccessAppearance(hasKana: hasKana, hasRomaji: hasRomaji && access != .locked)
        updateTapGesture()
    }

    private func applyAccessAppearance(hasKana: Bool? = nil, hasRomaji: Bool? = nil) {
        let hasKana = hasKana ?? !(storedKana?.isEmpty ?? true)
        let hasRomaji = hasRomaji ?? (!(storedRomaji?.isEmpty ?? true) && access != .locked)

        switch access {
        case .reference:
            alpha = 1
            kanaLabel.textColor = hasKana ? .label : .clear
            romajiLabel.textColor = hasRomaji ? .label : .clear
            configureAppearance()
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
            updateProgressBar(studyCount: 0)
        case .learning(let studyCount):
            alpha = 1
            kanaLabel.textColor = hasKana ? .label : .clear
            romajiLabel.textColor = hasRomaji ? .label : .clear
            configureAppearance()
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
            updateProgressBar(studyCount: studyCount)
        case .locked:
            updateProgressBar(studyCount: 0)
            alpha = 0.35
            kanaLabel.textColor = hasKana ? .tertiaryLabel : .clear
            romajiLabel.textColor = .clear
            backgroundColor = ExperimentPalette.cardSurface.withAlphaComponent(0.6)
            layer.shadowOpacity = 0
        }
        applySelectionChrome()
    }

    @objc private func cardTapped() {
        onTap?()
    }

    private func updateTapGesture() {
        let hasKana = !(storedKana?.isEmpty ?? true)
        let tappable = onTap != nil && hasKana && access != .locked
        isUserInteractionEnabled = tappable
        tapGesture.isEnabled = tappable
        if tappable {
            accessibilityTraits = isChartSelected ? [.button, .selected] : [.button]
            accessibilityLabel = [storedKana, storedRomaji].compactMap { $0 }.joined(separator: ", ")
            if isChartSelectionEnabled {
                accessibilityHint = isChartSelected
                    ? "Selected for review · double tap to deselect"
                    : "Select for review"
            } else if case .learning(let studyCount) = access {
                let percent = Int((KanaProgressSquareStyle.progressFraction(for: studyCount) * 100).rounded())
                accessibilityHint = "Shows detail · \(percent)% recall progress"
            } else {
                accessibilityHint = "Shows detail"
            }
        } else if access == .locked, hasKana {
            accessibilityTraits = []
            accessibilityLabel = "Locked"
            accessibilityHint = "Complete the lesson to unlock"
        } else {
            accessibilityTraits = []
            accessibilityLabel = nil
            accessibilityHint = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
        if presentation == .grid {
            applyTypography()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAccessAppearance()
        applySelectionChrome()
        configureShadow()
        setNeedsLayout()
    }

    private func configureShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
    }

    private func configureAppearance() {
        guard !isChartSelected else {
            applySelectionChrome()
            return
        }
        backgroundColor = ExperimentPalette.cardSurface
        if presentation == .detailHero {
            layer.borderWidth = ExperimentCardStroke.normalWidth
            layer.borderColor = ExperimentPalette.cardBorder
                .resolvedColor(with: traitCollection).cgColor
        } else {
            layer.borderWidth = 0
            layer.borderColor = nil
        }
    }

    private func applySelectionChrome() {
        guard isChartSelected, access != .locked else {
            if access != .locked {
                configureAppearance()
            }
            return
        }
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = 2
        layer.borderColor = UIColor.systemBlue.cgColor
    }

    private func updateProgressBar(studyCount: Int) {
        let showsProgress = presentation == .grid
            && { if case .learning = access { return true }; return false }()
        progressTrack.isHidden = !showsProgress
        stackCenterYConstraint?.constant = showsProgress ? -4 : 0

        guard showsProgress else { return }

        let fraction = max(KanaProgressSquareStyle.progressFraction(for: studyCount), 0.04)
        progressFillWidthConstraint?.isActive = false
        progressFillWidthConstraint = progressFill.widthAnchor.constraint(
            equalTo: progressTrack.widthAnchor,
            multiplier: fraction
        )
        progressFillWidthConstraint?.isActive = true
    }

    private func configure() {
        clipsToBounds = false
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        configureAppearance()
        configureShadow()
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        kanaLabel.adjustsFontForContentSizeCategory = true
        kanaLabel.textAlignment = .center
        kanaLabel.adjustsFontSizeToFitWidth = true
        kanaLabel.minimumScaleFactor = 0.65
        kanaLabel.maximumContentSizeCategory = .accessibilityLarge

        romajiLabel.adjustsFontForContentSizeCategory = true
        romajiLabel.textAlignment = .center
        romajiLabel.numberOfLines = 1

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.addArrangedSubview(kanaLabel)
        stack.addArrangedSubview(romajiLabel)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.backgroundColor = ExperimentPalette.progressBarTrack
        progressTrack.layer.cornerRadius = HiraganaChartMetrics.progressTrackHeight / 2
        progressTrack.layer.cornerCurve = .continuous
        progressTrack.clipsToBounds = true
        progressTrack.isHidden = true

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = KanaProgressSquareStyle.hiraganaBase

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(progressTrack)
        progressTrack.addSubview(progressFill)

        let height = heightAnchor.constraint(
            equalTo: widthAnchor,
            multiplier: HiraganaChartMetrics.kanaTileAspectHeightOverWidth
        )
        heightConstraint = height
        let centerY = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        stackCenterYConstraint = centerY
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            centerY,
            height,

            progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            progressTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            progressTrack.heightAnchor.constraint(equalToConstant: HiraganaChartMetrics.progressTrackHeight),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
        ])
        applyTypography()
    }

    private func applyTypography() {
        switch presentation {
        case .grid:
            // Scale text with card width so larger phones don't feel visually undersized.
            let width = max(bounds.width, 1)
            let isLearning = if case .learning = access { true } else { false }
            let kanaWidthScale: CGFloat = isLearning ? 0.36 : 0.46
            let kanaMaxSize: CGFloat = isLearning ? 34 : 44
            let kanaNominal = UIFont.preferredFont(forTextStyle: .title2).pointSize
            let kanaBase = min(max(width * kanaWidthScale, kanaNominal - (isLearning ? 3 : 0)), kanaMaxSize)
            let kanaMetrics = UIFontMetrics(forTextStyle: .title2)
            kanaLabel.font = kanaMetrics.scaledFont(
                for: .systemFont(ofSize: kanaBase, weight: .bold)
            )

            let romajiNominal = UIFont.preferredFont(forTextStyle: .footnote).pointSize
            let romajiBase = min(max(width * (isLearning ? 0.17 : 0.21), romajiNominal - (isLearning ? 1 : 0)), isLearning ? 17 : 21)
            let romajiMetrics = UIFontMetrics(forTextStyle: .footnote)
            romajiLabel.font = romajiMetrics.scaledFont(
                for: .systemFont(ofSize: romajiBase, weight: .regular)
            )
            stack.spacing = 2
            stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 2, bottom: 4, trailing: 2)
        case .detailHero:
            let kanaMetrics = UIFontMetrics(forTextStyle: .largeTitle)
            let kanaNominal = UIFont.preferredFont(forTextStyle: .largeTitle).pointSize + 6
            kanaLabel.font = kanaMetrics.scaledFont(for: .systemFont(ofSize: kanaNominal, weight: .bold))
            let romajiMetrics = UIFontMetrics(forTextStyle: .title3)
            let romajiNominal = UIFont.preferredFont(forTextStyle: .title3).pointSize
            romajiLabel.font = romajiMetrics.scaledFont(for: .systemFont(ofSize: romajiNominal, weight: .medium))
            stack.spacing = 0
            stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 4)
        }
    }
}

// MARK: - KanaChartRowView

final class KanaChartRowView: UIView {

    private let rowLabel = UILabel()
    private let cardsStack = UIStackView()
    private var kanaCards: [KanaCard] = []

    /// Leading row label (`""` preserves column alignment).
    /// Each slot matches one column header. Both `kana` and `romaji` `nil` → textbook gap (`sheetEmpty`).
    init(
        rowSound: String,
        cells: [(kana: String?, romaji: String?)],
        displayMode: KanaChartDisplayMode = .reference,
        onKanaInteraction: ((String, String) -> Void)? = nil
    ) {
        precondition(!cells.isEmpty)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rowLabel.font = .preferredFont(forTextStyle: .footnote)
        rowLabel.textColor = rowSound.isEmpty ? .clear : .secondaryLabel
        rowLabel.adjustsFontForContentSizeCategory = true
        rowLabel.numberOfLines = 1
        rowLabel.minimumScaleFactor = 0.6
        rowLabel.adjustsFontSizeToFitWidth = true
        rowLabel.textAlignment = .right
        rowLabel.text = rowSound.isEmpty ? " " : rowSound
        rowLabel.setContentHuggingPriority(.required, for: .horizontal)
        rowLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        cardsStack.axis = .horizontal
        cardsStack.spacing = 6
        cardsStack.distribution = .fillEqually
        cardsStack.translatesAutoresizingMaskIntoConstraints = false

        for spec in cells {
            if spec.kana == nil, spec.romaji == nil {
                cardsStack.addArrangedSubview(Self.sheetGapSubview())
                continue
            }
            let card = KanaCard()
            let access = Self.cardAccess(kana: spec.kana, displayMode: displayMode)
            card.setAccess(access)
            card.configure(kana: spec.kana, romaji: spec.romaji)
            if let kana = spec.kana, let romaji = spec.romaji {
                kanaCards.append(card)
                if access != .locked, let onKanaInteraction {
                    card.onTap = { onKanaInteraction(kana, romaji) }
                }
            }
            cardsStack.addArrangedSubview(card)
        }

        let horizontal = UIStackView(arrangedSubviews: [rowLabel, cardsStack])
        horizontal.axis = .horizontal
        horizontal.alignment = .center
        horizontal.spacing = HiraganaChartMetrics.prefixToGridSpacing
        horizontal.translatesAutoresizingMaskIntoConstraints = false
        rowLabel.widthAnchor.constraint(equalToConstant: HiraganaChartMetrics.prefixColumnWidth).isActive = true

        addSubview(horizontal)
        NSLayoutConstraint.activate([
            horizontal.leadingAnchor.constraint(equalTo: leadingAnchor),
            horizontal.trailingAnchor.constraint(equalTo: trailingAnchor),
            horizontal.topAnchor.constraint(equalTo: topAnchor),
            horizontal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(displayMode: KanaChartDisplayMode) {
        for card in kanaCards {
            guard let kana = card.kana else { continue }
            let access = Self.cardAccess(kana: kana, displayMode: displayMode)
            card.setAccess(access)
            card.configure(kana: kana, romaji: card.romaji)
        }
    }

    func setInteractionHandler(_ handler: ((String, String) -> Void)?) {
        for card in kanaCards {
            guard let kana = card.kana, let romaji = card.romaji else {
                card.onTap = nil
                continue
            }
            if let handler, !card.isLockedForInteraction {
                card.onTap = { handler(kana, romaji) }
            } else {
                card.onTap = nil
            }
        }
    }

    func allCards() -> [KanaCard] {
        kanaCards
    }

    private static func cardAccess(kana: String?, displayMode: KanaChartDisplayMode) -> KanaCardAccess {
        guard let kana, !kana.isEmpty else { return .reference }
        switch displayMode {
        case .reference:
            return .reference
        case .learning(let unlockedGlyphs, let studyCountForKana):
            guard unlockedGlyphs.contains(kana) else { return .locked }
            return .learning(studyCount: studyCountForKana(kana))
        }
    }

    private static func sheetGapSubview() -> UIView {
        let gap = UIView()
        gap.backgroundColor = .clear
        gap.isAccessibilityElement = false
        gap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gap.heightAnchor.constraint(
                equalTo: gap.widthAnchor,
                multiplier: HiraganaChartMetrics.kanaTileAspectHeightOverWidth
            ),
        ])
        return gap
    }
}

// MARK: - Chart display mode

enum KanaChartDisplayMode {
    case reference
    case learning(unlockedGlyphs: Set<String>, studyCountForKana: (String) -> Int)
}

// MARK: - KanaGridChartView

/// Shared column-header row + stacked `KanaRow`s (gojūon, yōon, …).
final class KanaGridChartView: UIView {

    enum GridKind {
        case seion
        case voiced
        case yoon
    }

    private var rowViews: [KanaChartRowView] = []

    fileprivate init(
        columnSuffixes: [String],
        rows: [KanaRow],
        displayMode: KanaChartDisplayMode = .reference,
        onKanaInteraction: ((String, String) -> Void)? = nil
    ) {
        precondition(!columnSuffixes.isEmpty)
        for row in rows {
            precondition(
                row.cells.count == columnSuffixes.count,
                "Row \(row.rowSound) cell count \(row.cells.count) != column count \(columnSuffixes.count)"
            )
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let leadingSpacer = UIView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: HiraganaChartMetrics.prefixColumnWidth).isActive = true

        let suffixStack = UIStackView(arrangedSubviews: columnSuffixes.map { suffix in
            let lbl = UILabel()
            lbl.text = suffix
            lbl.font = .preferredFont(forTextStyle: .footnote)
            lbl.textColor = .secondaryLabel
            lbl.adjustsFontForContentSizeCategory = true
            lbl.textAlignment = .center
            return lbl
        })
        suffixStack.axis = .horizontal
        suffixStack.spacing = 6
        suffixStack.translatesAutoresizingMaskIntoConstraints = false
        suffixStack.alignment = .center
        suffixStack.distribution = .fillEqually

        let headerRow = UIStackView(arrangedSubviews: [leadingSpacer, suffixStack])
        headerRow.axis = .horizontal
        headerRow.spacing = HiraganaChartMetrics.prefixToGridSpacing
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.alignment = .center

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.spacing = 8
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        for row in rows {
            let rowView = KanaChartRowView(
                rowSound: row.rowSound,
                cells: row.cells,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
            rowViews.append(rowView)
            bodyStack.addArrangedSubview(rowView)
        }

        let rootStack = UIStackView(arrangedSubviews: [headerRow, bodyStack])
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(displayMode: KanaChartDisplayMode) {
        rowViews.forEach { $0.update(displayMode: displayMode) }
    }

    func setInteractionHandler(_ handler: ((String, String) -> Void)?) {
        rowViews.forEach { $0.setInteractionHandler(handler) }
    }

    func allCards() -> [KanaCard] {
        rowViews.flatMap { $0.allCards() }
    }

    convenience init(
        kind: GridKind,
        script: KanaScript = .hiragana,
        displayMode: KanaChartDisplayMode = .reference,
        onKanaInteraction: ((String, String) -> Void)? = nil
    ) {
        switch (kind, script) {
        case (.seion, .hiragana):
            self.init(
                columnSuffixes: KanaCurriculum.vowelSuffixes,
                rows: KanaCurriculum.hiraganaSeionChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        case (.seion, .katakana):
            self.init(
                columnSuffixes: KanaCurriculum.vowelSuffixes,
                rows: KanaCurriculum.katakanaSeionChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        case (.voiced, .hiragana):
            self.init(
                columnSuffixes: KanaCurriculum.vowelSuffixes,
                rows: KanaCurriculum.hiraganaVoicedChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        case (.voiced, .katakana):
            self.init(
                columnSuffixes: KanaCurriculum.vowelSuffixes,
                rows: KanaCurriculum.katakanaVoicedChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        case (.yoon, .hiragana):
            self.init(
                columnSuffixes: KanaCurriculum.yoonColumnHeaders,
                rows: KanaCurriculum.hiraganaYoonChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        case (.yoon, .katakana):
            self.init(
                columnSuffixes: KanaCurriculum.yoonColumnHeaders,
                rows: KanaCurriculum.katakanaYoonChartRows,
                displayMode: displayMode,
                onKanaInteraction: onKanaInteraction
            )
        }
    }
}


