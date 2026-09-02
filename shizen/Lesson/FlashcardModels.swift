//
//  FlashcardModels.swift
//  shizen
//
//  Vocab data + the per-card view used by `FlashcardStackView` (DEBUG).
//

import InteractionKit
import UIKit

struct VocabFlashcard {
    let japanese: String
    let reading: String
    let english: String
}

enum VocabFlashcardBank {
    static let starter: [VocabFlashcard] = [
        VocabFlashcard(japanese: "食べる", reading: "たべる", english: "to eat"),
        VocabFlashcard(japanese: "飲む", reading: "のむ", english: "to drink"),
        VocabFlashcard(japanese: "行く", reading: "いく", english: "to go"),
        VocabFlashcard(japanese: "来る", reading: "くる", english: "to come"),
        VocabFlashcard(japanese: "見る", reading: "みる", english: "to see / to watch"),
        VocabFlashcard(japanese: "聞く", reading: "きく", english: "to listen / to ask"),
        VocabFlashcard(japanese: "話す", reading: "はなす", english: "to speak"),
        VocabFlashcard(japanese: "読む", reading: "よむ", english: "to read"),
        VocabFlashcard(japanese: "書く", reading: "かく", english: "to write"),
        VocabFlashcard(japanese: "買う", reading: "かう", english: "to buy"),
        VocabFlashcard(japanese: "ありがとう", reading: "ありがとう", english: "thank you"),
        VocabFlashcard(japanese: "こんにちは", reading: "こんにちは", english: "hello / good afternoon"),
    ]
}

// MARK: - Card view

/// Tap to reveal; right-swipe = "I know it", left-swipe = "review again".
/// Reveal shrinks the keyword and animates the definition into place — no card flip.
final class VocabFlashcardView: UIView {

    private let japaneseLabel = JapaneseFuriganaBuilder.makeTranscriptLabel(font: .systemFont(ofSize: 88, weight: .semibold))
    private let readingLabel = UILabel()
    private let englishLabel = UILabel()
    private let definitionStack = UIStackView()
    private let hintLabel = UILabel()

    private var japaneseCenterYConstraint: NSLayoutConstraint!
    private var japaneseTopConstraint: NSLayoutConstraint!
    private var definitionCenterYConstraint: NSLayoutConstraint!

    private static let revealedKeywordScale: CGFloat = 0.42
    private static let definitionEntryOffset: CGFloat = 22
    private static let hiddenDefinitionCenterYOffset: CGFloat = 16
    private static let revealedDefinitionCenterYOffset: CGFloat = 32
    /// Shifts the keyword up when furigana is visible so the glyph block looks centered.
    private static let furiganaOpticalCenterYOffset: CGFloat = -20

    private(set) var isRevealed = false
    private var japaneseText = ""
    /// Bumped on each reveal toggle so stale animation completions can't clobber state.
    private var revealAnimationGeneration = 0
    private var furiganaAnimationGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configure(with card: VocabFlashcard) {
        japaneseText = card.japanese
        applyJapaneseDisplay()
        readingLabel.text = card.reading == card.japanese ? "" : card.reading
        readingLabel.isHidden = readingLabel.text?.isEmpty ?? true
        englishLabel.text = card.english
        setRevealed(false, animated: false)
    }

    func refreshJapaneseDisplay(animated: Bool = false) {
        applyJapaneseDisplay(animated: animated)
    }

    private func applyJapaneseDisplay(animated: Bool = false) {
        let fontSize = Self.japaneseFontSize(for: japaneseText)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let showFurigana = JapaneseFuriganaSettings.showOnFlashcards
        let targetInsets = JapaneseFuriganaBuilder.flashcardTextInsets(for: font, showFurigana: showFurigana)

        guard animated else {
            JapaneseFuriganaBuilder.applyFlashcardDisplay(
                to: japaneseLabel,
                text: japaneseText,
                font: font,
                textColor: .label
            )
            updateJapaneseOpticalAlignment(animated: false)
            return
        }

        furiganaAnimationGeneration += 1
        let generation = furiganaAnimationGeneration
        japaneseLabel.layer.removeAllAnimations()

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.15,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                self.japaneseLabel.textInsets = targetInsets
                self.updateJapaneseOpticalAlignment(animated: false)
                self.layoutIfNeeded()
            }
        )

        UIView.transition(
            with: japaneseLabel,
            duration: 0.3,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: {
                guard generation == self.furiganaAnimationGeneration else { return }
                JapaneseFuriganaBuilder.applyFlashcardContent(
                    to: self.japaneseLabel,
                    text: self.japaneseText,
                    font: font,
                    textColor: .label,
                    showFurigana: showFurigana
                )
            }
        )
    }

    private func hiddenJapaneseCenterYOffset() -> CGFloat {
        guard !isRevealed, JapaneseFuriganaSettings.showOnFlashcards else { return 0 }
        return Self.furiganaOpticalCenterYOffset
    }

    private func updateJapaneseOpticalAlignment(animated: Bool) {
        let target = hiddenJapaneseCenterYOffset()
        guard japaneseCenterYConstraint.constant != target else { return }
        japaneseCenterYConstraint.constant = target
        guard animated else { return }
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.15,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: { self.layoutIfNeeded() }
        )
    }

    /// Scales the JP label down as character count grows so 2- and 6-character entries fill comparable visual space.
    private static func japaneseFontSize(for text: String) -> CGFloat {
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
        [layer, japaneseLabel.layer, definitionStack.layer, hintLabel.layer].forEach {
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
        japaneseCenterYConstraint.isActive = !revealed
        japaneseTopConstraint.isActive = revealed
        japaneseCenterYConstraint.constant = revealed ? 0 : hiddenJapaneseCenterYOffset()
        definitionCenterYConstraint.constant = revealed
            ? Self.revealedDefinitionCenterYOffset
            : Self.hiddenDefinitionCenterYOffset

        let scale = revealed ? Self.revealedKeywordScale : 1
        japaneseLabel.transform = CGAffineTransform(scaleX: scale, y: scale)

        hintLabel.alpha = revealed ? 0.55 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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

        japaneseLabel.textAlignment = .center
        japaneseLabel.adjustsFontSizeToFitWidth = true
        japaneseLabel.minimumScaleFactor = 0.5
        japaneseLabel.numberOfLines = 1
        japaneseLabel.clipsToBounds = false
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false

        readingLabel.font = .systemFont(ofSize: 26, weight: .regular)
        readingLabel.textColor = .secondaryLabel
        readingLabel.textAlignment = .center
        readingLabel.numberOfLines = 1
        readingLabel.adjustsFontSizeToFitWidth = true
        readingLabel.minimumScaleFactor = 0.5

        englishLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        englishLabel.textColor = .label
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0

        definitionStack.axis = .vertical
        definitionStack.alignment = .center
        definitionStack.spacing = 14
        definitionStack.translatesAutoresizingMaskIntoConstraints = false
        definitionStack.addArrangedSubview(readingLabel)
        definitionStack.addArrangedSubview(englishLabel)
        definitionStack.alpha = 0
        definitionStack.isHidden = true

        hintLabel.text = "Tap to reveal"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(japaneseLabel)
        addSubview(definitionStack)
        addSubview(hintLabel)

        japaneseCenterYConstraint = japaneseLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        japaneseTopConstraint = japaneseLabel.topAnchor.constraint(equalTo: topAnchor, constant: 40)
        japaneseTopConstraint.isActive = false

        definitionCenterYConstraint = definitionStack.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: Self.hiddenDefinitionCenterYOffset
        )

        NSLayoutConstraint.activate([
            japaneseLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            japaneseCenterYConstraint,
            japaneseLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            japaneseLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            definitionStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            definitionCenterYConstraint,
            definitionStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            definitionStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
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

extension VocabFlashcardView: StackableFlashcard {}

extension FlashcardStackView {
    func setDeck(_ deck: [VocabFlashcard]) {
        setDeck(count: deck.count) { index in
            let card = VocabFlashcardView()
            card.configure(with: deck[index])
            return card
        }
    }

    func refreshFuriganaDisplay(animated: Bool = true) {
        enumerateVisibleCards { card in
            (card as? VocabFlashcardView)?.refreshJapaneseDisplay(animated: animated)
        }
    }
}
