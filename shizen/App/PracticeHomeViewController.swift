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
        let header = makeSectionHeader(
            title: "Stacks",
            subtitle: "Tap a folder to see its words"
        )

        decksStack.axis = .vertical
        decksStack.spacing = 14
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

    private func makeSectionHeader(title: String, subtitle: String?) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        var arrangedSubviews: [UIView] = [titleLabel]
        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 0
            arrangedSubviews.append(subtitleLabel)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
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
        let dayKeys = DialogueProgressGridSupport.recentDayKeys()
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

        for folder in SavedVocabularyStore.shared.folders() {
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
        PracticeDeckPreview(
            id: folder.id,
            title: folder.name,
            subtitle: folder.subtitle,
            sampleJapanese: folder.sampleJapanese,
            accentLabel: folder.id == SavedVocabularyStore.inboxID ? "Inbox" : "Folder"
        )
    }

    // MARK: - Navigation

    private func startTodaysDialogue() {
        let dialogue = DialogueNestedPagingExperimentViewController(
            collectionID: DialogueScenarioCollectionCatalog.trainStationID,
            prefersNextIncompleteScenario: true
        )
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
    let accentLabel: String
}

// MARK: - Deck preview card

/// Home-row deck: mini layered flashcard stack + title/subtitle. Tap opens a
/// real swipe session (placeholder wiring → `FlashcardExperimentViewController`).
private final class PracticeDeckPreviewCardView: UIControl {

    var onTapped: (() -> Void)?

    private let cardView = UIView()
    private let miniStack = PracticeMiniFlashcardStackView()
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with deck: PracticeDeckPreview) {
        badgeLabel.text = deck.accentLabel.uppercased()
        titleLabel.text = deck.title
        subtitleLabel.text = deck.subtitle
        miniStack.configure(frontJapanese: deck.sampleJapanese)
    }

    private func configure() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.isUserInteractionEnabled = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .tertiaryLabel
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2

        let textColumn = UIStackView(arrangedSubviews: [badgeLabel, titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 4
        textColumn.alignment = .leading
        textColumn.setCustomSpacing(2, after: badgeLabel)
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.isUserInteractionEnabled = false

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.tintColor = .tertiaryLabel
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        miniStack.translatesAutoresizingMaskIntoConstraints = false
        miniStack.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [miniStack, textColumn, chevronView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false

        addSubview(cardView)
        cardView.addSubview(row)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            miniStack.widthAnchor.constraint(equalToConstant: 88),
            miniStack.heightAnchor.constraint(equalToConstant: 96),
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

/// Static 3-card stack that echoes `FlashcardStackView` geometry (scale + y-offset
/// + slight tilt on back cards) for home previews.
private final class PracticeMiniFlashcardStackView: UIView {

    private let backCard = UIView()
    private let midCard = UIView()
    private let frontCard = UIView()
    private let japaneseLabel = UILabel()

    private static let cardCornerRadius: CGFloat = 12
    private static let scaleRatio: CGFloat = 0.92
    private static let verticalOffset: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(frontJapanese: String) {
        japaneseLabel.text = frontJapanese
    }

    private func configure() {
        clipsToBounds = false
        backgroundColor = .clear

        [backCard, midCard, frontCard].forEach { card in
            card.translatesAutoresizingMaskIntoConstraints = false
            card.backgroundColor = ExperimentPalette.cardSurface
            card.layer.cornerRadius = Self.cardCornerRadius
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = ExperimentCardStroke.normalWidth
            card.layer.borderColor = ExperimentPalette.cardBorder.cgColor
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.1
            card.layer.shadowRadius = 4
            card.layer.shadowOffset = CGSize(width: 0, height: 2)
            addSubview(card)
        }

        // Draw back → mid → front.
        sendSubviewToBack(backCard)
        bringSubviewToFront(frontCard)

        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        japaneseLabel.textColor = .label
        japaneseLabel.textAlignment = .center
        japaneseLabel.adjustsFontSizeToFitWidth = true
        japaneseLabel.minimumScaleFactor = 0.5
        frontCard.addSubview(japaneseLabel)

        let cardWidth: CGFloat = 72
        let cardHeight: CGFloat = 80

        NSLayoutConstraint.activate([
            frontCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            frontCard.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            frontCard.widthAnchor.constraint(equalToConstant: cardWidth),
            frontCard.heightAnchor.constraint(equalToConstant: cardHeight),

            midCard.centerXAnchor.constraint(equalTo: frontCard.centerXAnchor),
            midCard.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
            midCard.widthAnchor.constraint(equalTo: frontCard.widthAnchor),
            midCard.heightAnchor.constraint(equalTo: frontCard.heightAnchor),

            backCard.centerXAnchor.constraint(equalTo: frontCard.centerXAnchor),
            backCard.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
            backCard.widthAnchor.constraint(equalTo: frontCard.widthAnchor),
            backCard.heightAnchor.constraint(equalTo: frontCard.heightAnchor),

            japaneseLabel.leadingAnchor.constraint(equalTo: frontCard.leadingAnchor, constant: 6),
            japaneseLabel.trailingAnchor.constraint(equalTo: frontCard.trailingAnchor, constant: -6),
            japaneseLabel.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
        ])

        applyStackTransforms()
    }

    private func applyStackTransforms() {
        midCard.transform = CGAffineTransform(translationX: 0, y: Self.verticalOffset)
            .scaledBy(x: Self.scaleRatio, y: Self.scaleRatio)
            .rotated(by: 4 * .pi / 180)
        backCard.transform = CGAffineTransform(translationX: 0, y: Self.verticalOffset * 2)
            .scaledBy(x: pow(Self.scaleRatio, 2), y: pow(Self.scaleRatio, 2))
            .rotated(by: -5.5 * .pi / 180)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            [backCard, midCard, frontCard].forEach {
                $0.layer.borderColor = ExperimentPalette.cardBorder.cgColor
                $0.backgroundColor = ExperimentPalette.cardSurface
                $0.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.1
            }
        }
    }
}
