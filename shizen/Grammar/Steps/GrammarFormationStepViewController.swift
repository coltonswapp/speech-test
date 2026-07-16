//
//  GrammarFormationStepViewController.swift
//  shizen
//
//  Formation + usage reference cards.
//

import UIKit
import GrammarContentKit

final class GrammarFormationStepViewController: LessonStepViewController {

    private let point: GrammarPoint
    private var collectionView: UICollectionView!

    private var headerRegistration: UICollectionView.SupplementaryRegistration<GrammarListSectionHeaderView>!
    private var formationCellRegistration: UICollectionView.CellRegistration<
        GrammarTeachingCardCell, [GrammarTeachingBlock]
    >!
    private var usageLadderCellRegistration: UICollectionView.CellRegistration<
        GrammarUsageLadderCell, GrammarUsageLadder
    >!
    private var usageLegacyCellRegistration: UICollectionView.CellRegistration<
        GrammarTeachingCardCell, [GrammarTeachingBlock]
    >!

    private enum Section: Int, CaseIterable {
        case formation
        case usage

        var title: String {
            switch self {
            case .formation: return "Formation"
            case .usage: return "Usage"
            }
        }
    }

    init(point: GrammarPoint) {
        self.point = point
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInstruction(nil)
        configureCTA(.continue_(), target: self, action: #selector(continueTapped))
        progressiveContainerCoordinator?.setLivesVisible(false)
        configureCollectionView()
        installLessonContent(collectionView, horizontalInset: 0)
    }

    private var usesUsageLadders: Bool {
        !point.usageLadders.isEmpty
    }

    private func configureCollectionView() {
        headerRegistration = UICollectionView.SupplementaryRegistration<GrammarListSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { supplementaryView, _, indexPath in
            guard let section = Section(rawValue: indexPath.section) else { return }
            supplementaryView.configure(title: section.title)
        }

        formationCellRegistration = UICollectionView.CellRegistration<
            GrammarTeachingCardCell, [GrammarTeachingBlock]
        > { cell, _, blocks in
            cell.configure(blocks: blocks)
        }

        usageLadderCellRegistration = UICollectionView.CellRegistration<GrammarUsageLadderCell, GrammarUsageLadder> {
            cell, _, ladder in
            cell.configure(ladder: ladder)
        }

        usageLegacyCellRegistration = UICollectionView.CellRegistration<
            GrammarTeachingCardCell, [GrammarTeachingBlock]
        > { cell, _, blocks in
            cell.configure(blocks: blocks)
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self else { return nil }
            guard self.rowCount(for: sectionIndex) > 0 else { return nil }

            guard let section = Section(rawValue: sectionIndex) else { return nil }
            return GrammarListSectionLayout.makeSection(
                title: section.title,
                showsSeparators: section == .usage && self.usesUsageLadders,
                layoutEnvironment: layoutEnvironment
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.selfSizingInvalidation = .disabled
        collectionView.dataSource = self
    }

    private func rowCount(for sectionIndex: Int) -> Int {
        guard let section = Section(rawValue: sectionIndex) else { return 0 }
        switch section {
        case .formation:
            return point.formation.isEmpty ? 0 : 1
        case .usage:
            if usesUsageLadders { return point.usageLadders.count }
            return point.usage.isEmpty ? 0 : 1
        }
    }

    @objc private func continueTapped() {
        advanceToNextStep()
    }
}

// MARK: - Teaching card cell

private final class GrammarTeachingCardCell: UICollectionViewCell {

    private let blocksStack = UIStackView()

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
        background.backgroundColor = ExperimentPalette.cardSurface
        background.cornerRadius = 16
        backgroundConfiguration = background

        blocksStack.axis = .vertical
        blocksStack.spacing = 12
        blocksStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blocksStack)

        NSLayoutConstraint.activate([
            blocksStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            blocksStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            blocksStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            blocksStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func configure(blocks: [GrammarTeachingBlock]) {
        blocksStack.arrangedSubviews.forEach { view in
            blocksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                blocksStack.addArrangedSubview(Self.makeDivider())
            }
            blocksStack.addArrangedSubview(Self.makeBlockStack(block: block))
        }
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
        attributes.size = CGSize(width: targetWidth, height: measured.height)
        return attributes
    }

    private static func makeBlockStack(block: GrammarTeachingBlock) -> UIStackView {
        let blockStack = UIStackView()
        blockStack.axis = .vertical
        blockStack.spacing = 6
        blockStack.alignment = .leading

        if let title = block.title, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.textColor = .secondaryLabel
            titleLabel.numberOfLines = 0
            titleLabel.text = title
            blockStack.addArrangedSubview(titleLabel)
        }

        blockStack.addArrangedSubview(makeBodyStack(for: block.body))

        return blockStack
    }

    private static func makeBodyStack(for body: String) -> UIStackView {
        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 4

        let regularFont = UIFont.preferredFont(forTextStyle: .body)
        let textColor = UIColor.label
        let furiganaInsets = JapaneseFuriganaBuilder.compactDisplayInsets(for: regularFont)

        let paragraphs = body.components(separatedBy: "\n\n")
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                bodyStack.addArrangedSubview(makeVerticalSpacer(8))
            }

            let lines = paragraph.components(separatedBy: "\n")
            for line in lines {
                guard !line.isEmpty else { continue }
                let font = line.contains("→") ? boldBodyFont() : regularFont

                if containsKanji(line) {
                    let label = FuriganaTranscriptLabel()
                    label.clipsToBounds = false
                    label.numberOfLines = 0
                    label.textAlignment = .natural
                    label.setContentCompressionResistancePriority(.required, for: .vertical)
                    JapaneseFuriganaBuilder.applyScrubDisplay(
                        to: label,
                        attributed: JapaneseFuriganaBuilder.scenarioAttributedString(
                            for: line,
                            font: font,
                            textColor: textColor
                        ),
                        contentInsets: furiganaInsets
                    )
                    bodyStack.addArrangedSubview(label)
                } else {
                    let label = UILabel()
                    label.numberOfLines = 0
                    label.textAlignment = .natural
                    label.font = font
                    label.textColor = textColor
                    label.text = line
                    bodyStack.addArrangedSubview(label)
                }
            }
        }

        return bodyStack
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func makeVerticalSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spacer.heightAnchor.constraint(equalToConstant: height),
        ])
        return spacer
    }

    private static func boldBodyFont() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return .boldSystemFont(ofSize: base.pointSize)
    }

    private static func makeDivider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        return line
    }
}

// MARK: - Usage ladder cell

private final class GrammarUsageLadderCell: UICollectionViewCell {

    private let contentStack = UIStackView()

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

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    func configure(ladder: GrammarUsageLadder) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let label = ladder.label, !label.isEmpty {
            let titleLabel = UILabel()
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.textColor = .secondaryLabel
            titleLabel.text = label
            contentStack.addArrangedSubview(titleLabel)
        }

        for level in ladder.levels {
            contentStack.addArrangedSubview(Self.makeLevelRow(level: level))
        }
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
        attributes.size = CGSize(width: targetWidth, height: measured.height)
        return attributes
    }

    private static func makeLevelRow(level: GrammarUsageLevel) -> UIStackView {
        let font = GrammarJapaneseTypography.usageLadderFont

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = GrammarJapaneseTypography.usageLadderMaxLines
        japaneseLabel.lineBreakMode = .byWordWrapping
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: JapaneseFuriganaBuilder.usageLadderAttributedString(
                for: level.japanese,
                font: font,
                textColor: .label
            ),
            contentInsets: JapaneseFuriganaBuilder.compactDisplayInsets(for: font)
        )

        let registerLabel = UILabel()
        registerLabel.font = .preferredFont(forTextStyle: .footnote)
        registerLabel.textColor = .tertiaryLabel
        registerLabel.numberOfLines = 1
        registerLabel.textAlignment = .right
        registerLabel.text = level.register
        registerLabel.setContentHuggingPriority(.required, for: .horizontal)
        registerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [japaneseLabel, registerLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.distribution = .fill
        return row
    }
}

// MARK: - Data source

extension GrammarFormationStepViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rowCount(for: section)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Unexpected section")
        }
        switch section {
        case .formation:
            return collectionView.dequeueConfiguredReusableCell(
                using: formationCellRegistration,
                for: indexPath,
                item: point.formation
            )
        case .usage:
            if usesUsageLadders {
                let ladder = point.usageLadders[indexPath.item]
                return collectionView.dequeueConfiguredReusableCell(
                    using: usageLadderCellRegistration,
                    for: indexPath,
                    item: ladder
                )
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: usageLegacyCellRegistration,
                for: indexPath,
                item: point.usage
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
