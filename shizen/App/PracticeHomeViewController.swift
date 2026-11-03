//
//  PracticeHomeViewController.swift
//  shizen
//
//  Practice tab: Daily Dialogue habit card + live vocabulary folders.
//

import UIKit

final class PracticeHomeViewController: UIViewController, MainTabScrollable {

    var mainTabScrollViews: [UIScrollView] { [scrollView] }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dailyDialogueCard = DailyDialogueCardView()
    private let decksStack = UIStackView()
    private let stacksSubtitleLabel = UILabel()
    private let progressStore = DialogueProgressStore.shared

    private static let horizontalInset: CGFloat = 16

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureScrollView()
        configureDailyDialogueSection()
        configureStacksSection()
        layoutViews()
        refreshPracticeContent()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPracticeContent),
            name: SavedVocabularyStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshDailyDialogueCard),
            name: DialogueProgressStore.didChange,
            object: nil
        )

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressStore.reload()
        refreshPracticeContent()
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
    }

    private func configureDailyDialogueSection() {
        dailyDialogueCard.translatesAutoresizingMaskIntoConstraints = false
        dailyDialogueCard.onStartTapped = { [weak self] in
            self?.startTodaysDialogue()
        }
        contentStack.addArrangedSubview(dailyDialogueCard)
    }

    private func configureStacksSection() {
        let header = makeSectionHeader(title: "Stacks", subtitleLabel: stacksSubtitleLabel)

        decksStack.axis = .vertical
        decksStack.spacing = 10
        decksStack.translatesAutoresizingMaskIntoConstraints = false

        let sectionStack = UIStackView(arrangedSubviews: [header, decksStack])
        sectionStack.axis = .vertical
        sectionStack.spacing = 12
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(sectionStack)
    }

    private func layoutViews() {
        view.addSubview(scrollView)
        let inset = Self.horizontalInset
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])
    }

    private func makeSectionHeader(title: String, subtitleLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 4
        // Match the leading edge of content inside the Daily Dialogue card (18pt inset).
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0)
        return stack
    }

    // MARK: - Data

    @objc private func refreshPracticeContent() {
        refreshDailyDialogueCard()
        reloadDeckCards()
    }

    @objc private func refreshDailyDialogueCard() {
        let dayKeys = DialogueProgressGridSupport.recentDayKeys(calendar: progressStore.progressCalendar)
        dailyDialogueCard.configure(
            dayKeys: dayKeys,
            completedCounts: DialogueProgressGridSupport.completedCounts(
                for: dayKeys,
                progressStore: progressStore
            )
        )
    }

    private func reloadDeckCards() {
        decksStack.arrangedSubviews.forEach { view in
            decksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let folders = SavedVocabularyStore.shared.folders()
        let totalWords = folders.reduce(0) { $0 + $1.items.count }
        switch totalWords {
        case 0: stacksSubtitleLabel.text = "No words saved yet"
        case 1: stacksSubtitleLabel.text = "1 word saved"
        default: stacksSubtitleLabel.text = "\(totalWords) words saved"
        }

        for folder in folders {
            let preview = Self.preview(for: folder)
            let card = PracticeDeckPreviewCardView()
            card.configure(with: preview)
            card.onTapped = { [weak self] in
                self?.openFolder(id: folder.id)
            }
            decksStack.addArrangedSubview(card)
        }
    }

    private static func preview(for folder: SavedVocabularyFolder) -> PracticeDeckPreview {
        // Front card shows the newest word; the next few trail under the title.
        let newestFirst = folder.items.sorted { $0.createdAt > $1.createdAt }
        return PracticeDeckPreview(
            id: folder.id,
            title: folder.name,
            subtitle: folder.subtitle,
            sampleJapanese: folder.sampleJapanese,
            recentWords: newestFirst.dropFirst().prefix(3).map(\.surface)
        )
    }

    // MARK: - Navigation

    private func startTodaysDialogue() {
        let dialogue = DialogueNestedPagingExperimentViewController(
            collectionID: DialogueScenarioCollectionCatalog.trainStationID,
            prefersNextIncompleteScenario: true
        )
        dialogue.analytics.source = "home"
        navigationController?.pushViewController(dialogue, animated: true)
    }

    private func openFolder(id: String) {
        navigationController?.pushViewController(
            SavedVocabularyListViewController(folderID: id),
            animated: true
        )
    }
}

// MARK: - Models

private struct PracticeDeckPreview {
    let id: String
    let title: String
    let subtitle: String
    let sampleJapanese: String
    let recentWords: [String]
}

// MARK: - Deck preview card

/// Home-row deck: mini layered flashcard stack + title/subtitle. Tap opens a
/// real swipe session (placeholder wiring → `FlashcardExperimentViewController`).
private final class PracticeDeckPreviewCardView: UIControl {

    var onTapped: (() -> Void)?

    private let cardView = UIView()
    private let miniStack = PracticeMiniFlashcardStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let recentWordsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with deck: PracticeDeckPreview) {
        titleLabel.text = deck.title
        subtitleLabel.text = deck.subtitle
        recentWordsLabel.text = deck.recentWords.joined(separator: " · ")
        recentWordsLabel.isHidden = deck.recentWords.isEmpty
        miniStack.configure(frontJapanese: deck.sampleJapanese)
    }

    private func configure() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.isUserInteractionEnabled = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2

        recentWordsLabel.font = .systemFont(ofSize: 14, weight: .regular)
        recentWordsLabel.textColor = .tertiaryLabel
        recentWordsLabel.numberOfLines = 1
        recentWordsLabel.lineBreakMode = .byTruncatingTail

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, recentWordsLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 2
        textColumn.alignment = .leading
        textColumn.setCustomSpacing(6, after: subtitleLabel)
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.isUserInteractionEnabled = false

        miniStack.translatesAutoresizingMaskIntoConstraints = false
        miniStack.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [miniStack, textColumn])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false

        addSubview(cardView)
        cardView.addSubview(row)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 18pt leading matches the Stacks header and Daily Dialogue card content.
            row.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            row.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            miniStack.widthAnchor.constraint(equalToConstant: 76),
            miniStack.heightAnchor.constraint(equalToConstant: 76),
        ])

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.cardView.alpha = self.isHighlighted ? 0.72 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                    : .identity
            }
        }
    }

    @objc private func handleTap() {
        UISelectionFeedbackGenerator().selectionChanged()
        onTapped?()
    }
}

// MARK: - Mini flashcard stack

/// Static 3-card fan for home previews: back cards peek out left and right with
/// a slight tilt so the deck reads as a stack at a glance.
private final class PracticeMiniFlashcardStackView: UIView {

    private let backCard = UIView()
    private let midCard = UIView()
    private let frontCard = UIView()
    private let japaneseLabel = UILabel()

    private static let cardSize = CGSize(width: 56, height: 64)
    private static let cardCornerRadius: CGFloat = 10
    private static let fanOffset: CGFloat = 6
    /// Width available to the front label (card width minus 5pt each side).
    private static let labelWidth: CGFloat = 46

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(frontJapanese: String) {
        japaneseLabel.text = frontJapanese
        // Single words stay big; longer phrases drop size and wrap to two lines
        // instead of truncating after a couple of characters.
        switch frontJapanese.count {
        case ...2:
            japaneseLabel.font = .systemFont(ofSize: 22, weight: .semibold)
            japaneseLabel.numberOfLines = 1
            japaneseLabel.adjustsFontSizeToFitWidth = true
        case 3:
            japaneseLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            japaneseLabel.numberOfLines = 1
            japaneseLabel.adjustsFontSizeToFitWidth = true
        default:
            japaneseLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            japaneseLabel.numberOfLines = 2
            japaneseLabel.adjustsFontSizeToFitWidth = false
        }
    }

    private func configure() {
        clipsToBounds = false
        backgroundColor = .clear

        [backCard, midCard, frontCard].forEach { card in
            card.translatesAutoresizingMaskIntoConstraints = false
            card.layer.cornerRadius = Self.cardCornerRadius
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = ExperimentCardStroke.normalWidth
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowRadius = 3
            card.layer.shadowOffset = CGSize(width: 0, height: 1)
            addSubview(card)
        }
        applyColors()

        // Draw back → mid → front.
        sendSubviewToBack(backCard)
        bringSubviewToFront(frontCard)

        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.textColor = .label
        japaneseLabel.textAlignment = .center
        japaneseLabel.lineBreakMode = .byTruncatingTail
        japaneseLabel.minimumScaleFactor = 0.6
        frontCard.addSubview(japaneseLabel)

        NSLayoutConstraint.activate([
            frontCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            frontCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            frontCard.widthAnchor.constraint(equalToConstant: Self.cardSize.width),
            frontCard.heightAnchor.constraint(equalToConstant: Self.cardSize.height),

            midCard.centerXAnchor.constraint(equalTo: frontCard.centerXAnchor),
            midCard.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
            midCard.widthAnchor.constraint(equalTo: frontCard.widthAnchor),
            midCard.heightAnchor.constraint(equalTo: frontCard.heightAnchor),

            backCard.centerXAnchor.constraint(equalTo: frontCard.centerXAnchor),
            backCard.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
            backCard.widthAnchor.constraint(equalTo: frontCard.widthAnchor),
            backCard.heightAnchor.constraint(equalTo: frontCard.heightAnchor),

            japaneseLabel.centerXAnchor.constraint(equalTo: frontCard.centerXAnchor),
            japaneseLabel.widthAnchor.constraint(equalToConstant: Self.labelWidth),
            japaneseLabel.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
        ])

        applyStackTransforms()
    }

    private func applyStackTransforms() {
        midCard.transform = CGAffineTransform(translationX: Self.fanOffset, y: 1)
            .rotated(by: 6 * .pi / 180)
        backCard.transform = CGAffineTransform(translationX: -Self.fanOffset, y: 2)
            .rotated(by: -7 * .pi / 180)
    }

    private func applyColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        [backCard, midCard, frontCard].forEach {
            $0.backgroundColor = ExperimentPalette.cardSurface
            $0.layer.borderColor = ExperimentPalette.cardBorder.cgColor
            $0.layer.shadowOpacity = isDark ? 0.35 : 0.08
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }
}
