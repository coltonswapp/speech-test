//
//  GrammarPrincipleStepViewController.swift
//  shizen
//
//  Introduces a grammar point: meaning, pattern formula, then example lists.
//

import UIKit

final class GrammarPrincipleStepViewController: LessonStepViewController {

    enum Presentation {
        case lessonStep
        case referenceDetail
    }

    private let point: GrammarPoint
    private let presentation: Presentation
    private let contextLineID: String?
    private let primaryExamples: [GrammarExample]
    private let alternativeExamples: [GrammarExample]
    private let audioPlayer = GrammarAudioPlayer()
    private var collectionView: UICollectionView!

    private var headerRegistration: UICollectionView.SupplementaryRegistration<GrammarListSectionHeaderView>!
    private var heroCellRegistration: UICollectionView.CellRegistration<GrammarPrincipleHeroCell, Void>!
    private var exampleCellRegistration: UICollectionView.CellRegistration<GrammarExampleListCell, GrammarExample>!

    private var activeSections: [Section] {
        [.hero, .examples, .alternatives]
    }

    private enum Section: Int, CaseIterable {
        case hero
        case examples
        case alternatives

        var title: String? {
            switch self {
            case .hero: return nil
            case .examples: return "Examples"
            case .alternatives: return "Alternatives"
            }
        }
    }

    init(
        point: GrammarPoint,
        presentation: Presentation = .lessonStep,
        contextLineID: String? = nil
    ) {
        self.point = point
        self.presentation = presentation
        self.contextLineID = contextLineID
        primaryExamples = point.primaryExamples
        alternativeExamples = point.alternativeExamples
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch presentation {
        case .lessonStep:
            configureInstruction("New grammar")
            configureCTA(.continue_(), target: self, action: #selector(continueTapped))
            progressiveContainerCoordinator?.setLivesVisible(false)
        case .referenceDetail:
            configureInstruction(nil)
            configureReferenceDetailChrome()
            title = point.pattern
            navigationItem.largeTitleDisplayMode = .never
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Practice",
                primaryAction: UIAction { [weak self] _ in
                    self?.practiceTapped()
                }
            )
        }
        configureCollectionView()
        layoutCollectionView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateReferenceDetailScrollInsetsIfNeeded()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateReferenceDetailScrollInsetsIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard presentation == .referenceDetail else { return }
        GrammarMasteryStore.shared.recordEncounter(grammarID: point.id, scenarioID: contextLineID)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        audioPlayer.stop()
    }

    @objc private func continueTapped() {
        advanceToNextStep()
    }

    @objc private func practiceTapped() {
        GrammarPracticeCoordinator.present(for: point, from: self)
    }

    private func playExample(_ example: GrammarExample) {
        let dialogueLines = GrammarExampleDialogueLines.lines(for: example)
        audioPlayer.play(
            publishedAudioUrl: example.publishedAudioUrl,
            audioKey: example.audioKey,
            dialogueLines: dialogueLines,
            fallbackText: example.japanese
        )
    }

    private func configureCollectionView() {
        headerRegistration = UICollectionView.SupplementaryRegistration<GrammarListSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] supplementaryView, _, indexPath in
            guard
                let self,
                let section = self.section(at: indexPath.section),
                let title = section.title
            else { return }
            supplementaryView.configure(title: title)
        }

        heroCellRegistration = UICollectionView.CellRegistration<GrammarPrincipleHeroCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(
                point: self.point,
                instruction: self.presentation == .referenceDetail ? nil : self.instructionLabel.text,
                style: .lessonIntro
            )
        }

        exampleCellRegistration = UICollectionView.CellRegistration<GrammarExampleListCell, GrammarExample> {
            [weak self] cell, _, example in
            cell.configure(example: example) { [weak self] in
                self?.playExample(example)
            }
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self, let section = self.section(at: sectionIndex) else { return nil }
            switch section {
            case .hero:
                return InsetGroupedDetailSectionLayout.makeCompositionalHeroSection(
                    estimatedHeight: 240,
                    contentInsets: NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20)
                )
            case .examples, .alternatives:
                let section = self.section(at: sectionIndex)
                let title = self.rowCount(for: sectionIndex) > 0 ? section?.title : nil
                return GrammarListSectionLayout.makeSection(
                    title: title,
                    showsSeparators: true,
                    layoutEnvironment: layoutEnvironment
                )
            }
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.selfSizingInvalidation = .disabled
        collectionView.dataSource = self
        collectionView.delegate = self
        
    }

    private func layoutCollectionView() {
        installLessonContent(collectionView, horizontalInset: 0)
        updateReferenceDetailScrollInsetsIfNeeded()
    }

    private func updateReferenceDetailScrollInsetsIfNeeded() {
        guard presentation == .referenceDetail else { return }
        let topInset = view.safeAreaInsets.top
        guard topInset > 0 else { return }
        collectionView.applyMainTabTopInset(topInset)
    }

    private func section(at index: Int) -> Section? {
        guard activeSections.indices.contains(index) else { return nil }
        return activeSections[index]
    }

    private func rowCount(for sectionIndex: Int) -> Int {
        guard let section = section(at: sectionIndex) else { return 0 }
        switch section {
        case .hero: return 1
        case .examples: return primaryExamples.count
        case .alternatives: return alternativeExamples.count
        }
    }

    private func example(at indexPath: IndexPath) -> GrammarExample? {
        guard let section = section(at: indexPath.section) else { return nil }
        switch section {
        case .hero: return nil
        case .examples:
            guard indexPath.item < primaryExamples.count else { return nil }
            return primaryExamples[indexPath.item]
        case .alternatives:
            guard indexPath.item < alternativeExamples.count else { return nil }
            return alternativeExamples[indexPath.item]
        }
    }
}

// MARK: - Hero cell

private final class GrammarPrincipleHeroCell: UICollectionViewCell {

    enum Style {
        case lessonIntro
        case referenceDetail
    }

    private let instructionLabel = UILabel()
    private let meaningLabel = UILabel()
    private let readingLabel = UILabel()
    private let blurbLabel = UILabel()
    private let patternsLabel = UILabel()

    private static var meaningFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title2)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }

    private static var patternFont: UIFont {
        .systemFont(ofSize: 20, weight: .medium)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .clear
        backgroundConfiguration = background

        LessonInstructionLabel.apply(to: instructionLabel)

        meaningLabel.font = Self.meaningFont
        meaningLabel.textColor = .label
        meaningLabel.numberOfLines = 0
        meaningLabel.textAlignment = .center

        readingLabel.font = .preferredFont(forTextStyle: .subheadline)
        readingLabel.textColor = .secondaryLabel
        readingLabel.numberOfLines = 0
        readingLabel.textAlignment = .center
        readingLabel.isHidden = true

        blurbLabel.font = .preferredFont(forTextStyle: .body)
        blurbLabel.textColor = .secondaryLabel
        blurbLabel.numberOfLines = 0
        blurbLabel.textAlignment = .center

        patternsLabel.numberOfLines = 0
        patternsLabel.textAlignment = .center

        let contentStack = UIStackView(arrangedSubviews: [
            instructionLabel, meaningLabel, readingLabel, patternsLabel, blurbLabel,
        ])
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.setCustomSpacing(8, after: instructionLabel)
        contentStack.setCustomSpacing(6, after: meaningLabel)
        contentStack.setCustomSpacing(10, after: readingLabel)
        contentStack.setCustomSpacing(10, after: patternsLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = layoutAttributes.size.width
        let fittingSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let measured = contentView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = max(measured.height, 200)
        attributes.size = CGSize(width: targetWidth, height: height)
        return attributes
    }

    func configure(point: GrammarPoint, instruction: String?, style: Style = .lessonIntro) {
        switch style {
        case .lessonIntro:
            instructionLabel.text = instruction
            instructionLabel.isHidden = instruction?.isEmpty != false
            meaningLabel.text = point.shortDefinition
            readingLabel.isHidden = true
            patternsLabel.attributedText = Self.attributedPatterns(point.primaryPatternForms)
            patternsLabel.isHidden = point.primaryPatternForms.isEmpty
            blurbLabel.text = point.blurb
            blurbLabel.isHidden = point.blurb?.isEmpty != false
        case .referenceDetail:
            instructionLabel.isHidden = true
            meaningLabel.font = GrammarJapaneseTypography.drillPromptFont
            meaningLabel.text = point.pattern
            readingLabel.text = point.reading
            readingLabel.isHidden = point.reading.isEmpty
            patternsLabel.attributedText = Self.attributedPatterns(point.primaryPatternForms)
            patternsLabel.isHidden = point.primaryPatternForms.isEmpty
            blurbLabel.font = .preferredFont(forTextStyle: .title3)
            blurbLabel.textColor = .label
            if let blurb = point.blurb, !blurb.isEmpty {
                blurbLabel.text = "\(point.shortDefinition)\n\n\(blurb)"
            } else {
                blurbLabel.text = point.shortDefinition
            }
            blurbLabel.isHidden = point.shortDefinition.isEmpty && point.blurb?.isEmpty != false
        }
    }

    private static func attributedPatterns(_ forms: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, form) in forms.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(attributedPattern(form: form))
        }
        return result
    }

    private static func attributedPattern(form: String) -> NSAttributedString {
        let font = patternFont
        let secondary: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let primary: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        let line = NSMutableAttributedString(string: "___", attributes: secondary)
        line.append(NSAttributedString(string: " + ", attributes: secondary))
        line.append(NSAttributedString(string: form, attributes: primary))
        return line
    }
}

// MARK: - Example cell

private final class GrammarExampleListCell: UICollectionViewCell {

    private let japaneseLabel = FuriganaTranscriptLabel()
    private let englishLabel = UILabel()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()
    private let playControl = LessonAudioReplayButton(size: 44, glyphPointSize: 18, glyphDimension: 22)
    private var onPlay: (() -> Void)?

    private static let japaneseFont = GrammarJapaneseTypography.listExampleFont
    private static let japaneseEnglishSpacing = GrammarJapaneseTypography.listExampleJapaneseEnglishSpacing

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.cornerRadius = 12
        backgroundConfiguration = background

        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        englishLabel.font = GrammarJapaneseTypography.listExampleEnglishFont
        englishLabel.textColor = .secondaryLabel
        englishLabel.numberOfLines = 0
        englishLabel.textAlignment = .natural

        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Self.japaneseEnglishSpacing
        textStack.addArrangedSubview(japaneseLabel)
        textStack.addArrangedSubview(englishLabel)

        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(textStack)
        rowStack.addArrangedSubview(playControl)

        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playControl.setContentHuggingPriority(.required, for: .horizontal)
        playControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        playControl.addTarget(self, action: #selector(playTapped))

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rowStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -(12 + GrammarJapaneseTypography.listExampleRowBottomInset)
            ),
        ])
    }

    @objc private func playTapped() {
        onPlay?()
    }

    func configure(example: GrammarExample, onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        let font = Self.japaneseFont
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: example.japanese,
                font: font,
                textColor: .label
            ),
            contentInsets: JapaneseFuriganaBuilder.compactDisplayInsets(for: font)
        )
        englishLabel.text = example.english
    }
}

// MARK: - Data source

extension GrammarPrincipleStepViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        activeSections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rowCount(for: section)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let section = section(at: indexPath.section) else {
            fatalError("Unexpected section")
        }
        switch section {
        case .hero:
            return collectionView.dequeueConfiguredReusableCell(
                using: heroCellRegistration,
                for: indexPath,
                item: ()
            )
        case .examples, .alternatives:
            guard let example = example(at: indexPath) else {
                fatalError("Missing example")
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: exampleCellRegistration,
                for: indexPath,
                item: example
            )
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueConfiguredReusableSupplementary(
            using: headerRegistration,
            for: indexPath
        )
    }
}

extension GrammarPrincipleStepViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }
}
