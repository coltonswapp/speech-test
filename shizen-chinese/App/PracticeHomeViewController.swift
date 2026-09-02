//
//  PracticeHomeViewController.swift
//  shizen-chinese
//
//  Practice tab: daily inbox card + saved flashcard stacks.
//

import UIKit

final class PracticeHomeViewController: UIViewController, MainTabScrollable {

    var mainTabScrollViews: [UIScrollView] { [scrollView] }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dailyPracticeCard = DailyInboxCardView()
    private let decksStack = UIStackView()

    private static let horizontalInset: CGFloat = 16

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureScrollView()
        configureDailyPracticeSection()
        configureStacksSection()
        layoutViews()
        reloadDeckCards()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadDeckCards),
            name: DeckStore.didChangeNotification,
            object: nil
        )

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadDeckCards()
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

    private func configureDailyPracticeSection() {
        dailyPracticeCard.translatesAutoresizingMaskIntoConstraints = false
        dailyPracticeCard.onStartTapped = { [weak self] in
            self?.openFlashcards(deckID: DeckStore.inboxID, title: "Inbox")
        }
        contentStack.addArrangedSubview(dailyPracticeCard)
    }

    private func configureStacksSection() {
        let header = makeSectionHeader(
            title: "Stacks",
            subtitle: "Swipe to clear · tap a deck to practice"
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
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0)
        return stack
    }

    // MARK: - Data

    @objc private func reloadDeckCards() {
        dailyPracticeCard.configure(dueCount: DeckStore.shared.inbox.dueCount)

        decksStack.arrangedSubviews.forEach { view in
            decksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for deck in DeckStore.shared.decks {
            let card = PracticeDeckPreviewCardView()
            card.configure(with: deck)
            card.onTapped = { [weak self] in
                self?.openFlashcards(deckID: deck.id, title: deck.name)
            }
            decksStack.addArrangedSubview(card)
        }
    }

    private func openFlashcards(deckID: String, title: String) {
        let flashcards = FlashcardReviewViewController(deckID: deckID)
        flashcards.title = title
        navigationController?.pushViewController(flashcards, animated: true)
    }
}

// MARK: - Daily Inbox card

private final class DailyInboxCardView: UIView {

    var onStartTapped: (() -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let startButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(dueCount: Int) {
        if dueCount == 0 {
            subtitleLabel.text = "Nothing due. Save words from the dictionary, then start here."
            startButton.configuration?.title = "Review"
        } else {
            subtitleLabel.text = dueCount == 1
                ? "1 word waiting in Inbox."
                : "\(dueCount) words waiting in Inbox."
            startButton.configuration?.title = "Start"
        }
    }

    private func configure() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.text = "Daily Practice"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 6
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Start"
        buttonConfig.baseBackgroundColor = Colors.brandYellow
        buttonConfig.baseForegroundColor = Colors.textYellow
        buttonConfig.cornerStyle = .capsule
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .bold)
            return outgoing
        }
        startButton.configuration = buttonConfig
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(handleStartTapped), for: .touchUpInside)

        let rowStack = UIStackView(arrangedSubviews: [textColumn, startButton])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(rowStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            rowStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            rowStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            rowStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),

            startButton.heightAnchor.constraint(equalToConstant: 36),
            startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    @objc private func handleStartTapped() {
        onStartTapped?()
    }
}

// MARK: - Deck preview card

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

    func configure(with deck: WordDeck) {
        badgeLabel.text = deck.id == DeckStore.inboxID ? "INBOX" : "DECK"
        titleLabel.text = deck.name
        subtitleLabel.text = deck.subtitle
        miniStack.configure(frontHanzi: deck.sampleHanzi)
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

private final class PracticeMiniFlashcardStackView: UIView {

    private let backCard = UIView()
    private let midCard = UIView()
    private let frontCard = UIView()
    private let hanziLabel = UILabel()

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

    func configure(frontHanzi: String) {
        hanziLabel.text = frontHanzi
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

        sendSubviewToBack(backCard)
        bringSubviewToFront(frontCard)

        hanziLabel.translatesAutoresizingMaskIntoConstraints = false
        hanziLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        hanziLabel.textColor = .label
        hanziLabel.textAlignment = .center
        hanziLabel.adjustsFontSizeToFitWidth = true
        hanziLabel.minimumScaleFactor = 0.5
        frontCard.addSubview(hanziLabel)

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

            hanziLabel.leadingAnchor.constraint(equalTo: frontCard.leadingAnchor, constant: 6),
            hanziLabel.trailingAnchor.constraint(equalTo: frontCard.trailingAnchor, constant: -6),
            hanziLabel.centerYAnchor.constraint(equalTo: frontCard.centerYAnchor),
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
