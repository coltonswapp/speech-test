//
//  FlashcardReviewViewController.swift
//  shizen-chinese
//
//  Swipeable review: hanzi face, pinyin + English on reveal.
//  Right = know (clears due), left = again (stays due).
//

import InteractionKit
import UIKit

final class FlashcardReviewViewController: UIViewController {

    private let deckID: String
    private let stackView = FlashcardStackView()
    private let instructionsLabel = UILabel()
    private let emptyLabel = UILabel()

    private var cards: [DeckCard] = []

    init(deckID: String) {
        self.deckID = deckID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionsLabel.text = "Swipe right if you know it · left to review again · tap to reveal · book for dictionary"
        instructionsLabel.font = .preferredFont(forTextStyle: .footnote)
        instructionsLabel.textColor = .tertiaryLabel
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Nothing to review.\nSave words from the dictionary."
        emptyLabel.font = .preferredFont(forTextStyle: .title3)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.delegate = self

        view.addSubview(stackView)
        view.addSubview(instructionsLabel)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: instructionsLabel.topAnchor, constant: -16),

            instructionsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            instructionsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        loadDeck()
    }

    private func loadDeck() {
        cards = DeckStore.shared.reviewCards(in: deckID)
        let isEmpty = cards.isEmpty
        stackView.isHidden = isEmpty
        instructionsLabel.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty
        guard !isEmpty else { return }
        stackView.setDeck(count: cards.count) { [weak self] index in
            let card = ChineseFlashcardView()
            if let self {
                let deckCard = self.cards[index]
                card.configure(with: deckCard)
                card.onLookup = { [weak self] in
                    self?.openDictionary(for: deckCard.simplified)
                }
            }
            return card
        }
    }

    private func openDictionary(for simplified: String) {
        let trimmed = simplified.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        navigationController?.pushViewController(
            WordDictionaryDetailViewController(surface: trimmed),
            animated: true
        )
    }
}

extension FlashcardReviewViewController: FlashcardStackViewDelegate {
    func flashcardStack(_ stack: FlashcardStackView, didTapCardAt index: Int) {}

    func flashcardStack(_ stack: FlashcardStackView, didSwipeCardAt index: Int, direction: FlashcardSwipeDirection) {
        guard cards.indices.contains(index) else { return }
        DeckStore.shared.markReviewed(
            deckID: deckID,
            cardID: cards[index].id,
            known: direction == .right
        )
    }

    func flashcardStackDidFinish(_ stack: FlashcardStackView) {
        instructionsLabel.text = "All done"
    }
}

// MARK: - Card face

final class ChineseFlashcardView: UIView {

    var onLookup: (() -> Void)?

    private let hanziLabel = UILabel()
    private let pinyinLabel = UILabel()
    private let englishLabel = UILabel()
    private let definitionStack = UIStackView()
    private let hintLabel = UILabel()
    private let lookupButton = UIButton(type: .system)

    private var hanziCenterYConstraint: NSLayoutConstraint!
    private var hanziTopConstraint: NSLayoutConstraint!
    private var definitionCenterYConstraint: NSLayoutConstraint!

    private static let revealedKeywordScale: CGFloat = 0.42
    private static let definitionEntryOffset: CGFloat = 22
    private static let hiddenDefinitionCenterYOffset: CGFloat = 16
    private static let revealedDefinitionCenterYOffset: CGFloat = 32

    private(set) var isRevealed = false
    private var revealAnimationGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configure(with card: DeckCard) {
        hanziLabel.text = card.simplified
        hanziLabel.font = .systemFont(ofSize: Self.hanziFontSize(for: card.simplified), weight: .semibold)
        pinyinLabel.text = card.pinyinMarked
        englishLabel.text = card.glossary
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "\n")
        setRevealed(false, animated: false)
    }

    private static func hanziFontSize(for text: String) -> CGFloat {
        switch text.count {
        case ...2: return 88
        case 3: return 72
        case 4: return 60
        case 5: return 50
        case 6: return 44
        default: return 38
        }
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        revealAnimationGeneration += 1
        let generation = revealAnimationGeneration

        hintLabel.text = revealed ? "Tap to hide" : "Tap to reveal"

        guard animated else {
            applyRevealedVisualState(revealed)
            return
        }

        cancelRevealAnimations()
        prepareDefinitionStackForAnimation(revealed: revealed)

        let applyLayout = {
            self.applyRevealedLayout(revealed)
            self.layoutIfNeeded()
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.65,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: applyLayout
        )

        UIView.animate(
            withDuration: revealed ? 0.3 : 0.2,
            delay: 0,
            usingSpringWithDamping: revealed ? 0.88 : 1,
            initialSpringVelocity: revealed ? 0.85 : 0.4,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.definitionStack.alpha = revealed ? 1 : 0
                self.definitionStack.transform = revealed
                    ? .identity
                    : CGAffineTransform(translationX: 0, y: Self.definitionEntryOffset)
            },
            completion: { _ in
                self.finishRevealAnimation(generation: generation)
            }
        )
    }

    private func cancelRevealAnimations() {
        [layer, hanziLabel.layer, definitionStack.layer, hintLabel.layer].forEach {
            $0.removeAllAnimations()
        }
    }

    private func prepareDefinitionStackForAnimation(revealed: Bool) {
        if revealed {
            definitionStack.isHidden = false
        }
    }

    private func finishRevealAnimation(generation: Int) {
        guard generation == revealAnimationGeneration else { return }
        applyDefinitionVisibility(forRevealed: isRevealed)
    }

    private func applyRevealedVisualState(_ revealed: Bool) {
        cancelRevealAnimations()
        prepareDefinitionStackForAnimation(revealed: revealed)
        applyRevealedLayout(revealed)
        applyDefinitionVisibility(forRevealed: revealed)
        layoutIfNeeded()
    }

    private func applyDefinitionVisibility(forRevealed revealed: Bool) {
        if revealed {
            definitionStack.isHidden = false
            definitionStack.alpha = 1
            definitionStack.transform = .identity
        } else {
            definitionStack.alpha = 0
            definitionStack.transform = CGAffineTransform(translationX: 0, y: Self.definitionEntryOffset)
            definitionStack.isHidden = true
        }
    }

    private func applyRevealedLayout(_ revealed: Bool) {
        hanziCenterYConstraint.isActive = !revealed
        hanziTopConstraint.isActive = revealed

        definitionCenterYConstraint.constant = revealed
            ? Self.revealedDefinitionCenterYOffset
            : Self.hiddenDefinitionCenterYOffset

        let scale = revealed ? Self.revealedKeywordScale : 1
        hanziLabel.transform = CGAffineTransform(scaleX: scale, y: scale)

        hintLabel.alpha = revealed ? 0.55 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bringSubviewToFront(lookupButton)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureAppearance()
        configureShadow()
        setNeedsLayout()
    }

    private func configure() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.masksToBounds = false
        configureAppearance()
        configureShadow()
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        hanziLabel.textAlignment = .center
        hanziLabel.adjustsFontSizeToFitWidth = true
        hanziLabel.minimumScaleFactor = 0.5
        hanziLabel.numberOfLines = 1
        hanziLabel.translatesAutoresizingMaskIntoConstraints = false

        pinyinLabel.font = .systemFont(ofSize: 26, weight: .regular)
        pinyinLabel.textColor = .secondaryLabel
        pinyinLabel.textAlignment = .center
        pinyinLabel.numberOfLines = 1
        pinyinLabel.adjustsFontSizeToFitWidth = true
        pinyinLabel.minimumScaleFactor = 0.5

        englishLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        englishLabel.textColor = .label
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0

        definitionStack.axis = .vertical
        definitionStack.alignment = .center
        definitionStack.spacing = 14
        definitionStack.translatesAutoresizingMaskIntoConstraints = false
        definitionStack.addArrangedSubview(pinyinLabel)
        definitionStack.addArrangedSubview(englishLabel)
        definitionStack.alpha = 0
        definitionStack.isHidden = true

        hintLabel.text = "Tap to reveal"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        var lookupConfig = UIButton.Configuration.plain()
        lookupConfig.image = UIImage(systemName: "character.book.closed")
        lookupConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        lookupConfig.baseForegroundColor = .secondaryLabel
        lookupConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        lookupButton.configuration = lookupConfig
        lookupButton.translatesAutoresizingMaskIntoConstraints = false
        lookupButton.accessibilityLabel = "Look up in dictionary"
        lookupButton.addAction(UIAction { [weak self] _ in
            UISelectionFeedbackGenerator().selectionChanged()
            self?.onLookup?()
        }, for: .touchUpInside)

        addSubview(hanziLabel)
        addSubview(definitionStack)
        addSubview(hintLabel)
        addSubview(lookupButton)

        hanziCenterYConstraint = hanziLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        hanziTopConstraint = hanziLabel.topAnchor.constraint(equalTo: topAnchor, constant: 40)
        hanziTopConstraint.isActive = false

        definitionCenterYConstraint = definitionStack.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: Self.hiddenDefinitionCenterYOffset
        )

        NSLayoutConstraint.activate([
            hanziLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hanziCenterYConstraint,
            hanziLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            hanziLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            definitionStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            definitionCenterYConstraint,
            definitionStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            definitionStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: lookupButton.trailingAnchor, constant: 4),

            lookupButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            lookupButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            lookupButton.widthAnchor.constraint(equalToConstant: 44),
            lookupButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureAppearance() {
        backgroundColor = ExperimentPalette.cardSurface
    }

    private func configureShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.12
    }
}

extension ChineseFlashcardView: StackableFlashcard {}
