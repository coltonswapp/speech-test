//
//  KanaLessonEncouragementStepViewController.swift
//  shizen
//
//  Mid-lesson break: gradient, learned character cards, combo/praise badges, tutor audio via notch.
//

import UIKit

final class KanaLessonEncouragementStepViewController: LessonStepViewController {

    private let comboStreak: Int
    private let clipIndex: Int
    private let glyphs: [(kana: String, romaji: String)]

    private let gradientBackgroundView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let characterFan = EncouragementCharacterFanView()
    private let comboBadge: EncouragementBadgeView
    private let praiseBadge: EncouragementBadgeView
    private var didStartPresentation = false

    private static let comboFill = UIColor(red: 0.87, green: 0.94, blue: 1.0, alpha: 1)
    private static let comboText = UIColor(red: 0.05, green: 0.58, blue: 0.96, alpha: 1)
    private static let tensaiFill = UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1)
    private static let tensaiText = UIColor(red: 0.93, green: 0.72, blue: 0.0, alpha: 1)

    init(
        comboStreak: Int,
        clipIndex: Int,
        glyphs: [(kana: String, romaji: String)],
        praisePhrase: String = KanaLessonEncouragementPhraseBank.randomPhrase()
    ) {
        self.comboStreak = comboStreak
        self.clipIndex = clipIndex
        self.glyphs = glyphs
        self.comboBadge = EncouragementBadgeView(
            text: "COMBO \(comboStreak)x!",
            fillColor: Self.comboFill,
            textColor: Self.comboText
        )
        self.praiseBadge = EncouragementBadgeView(
            text: praisePhrase,
            fillColor: Self.tensaiFill,
            textColor: Self.tensaiText
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        installGradientBackground()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressiveContainerCoordinator?.setLessonHeaderHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartPresentation else { return }
        didStartPresentation = true
        characterFan.playEntryAnimation()
        playCascadeBadgeAnimations()
        DispatchQueue.main.async { [weak self] in
            self?.presentNotchEncouragement()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            progressiveContainerCoordinator?.dismissNotchDropIfNeeded()
            progressiveContainerCoordinator?.setLessonHeaderHidden(false, animated: animated)
        }
    }

    private func presentNotchEncouragement() {
        progressiveContainerCoordinator?.presentEncouragementNotchDrop(
            clipIndex: clipIndex,
            windowScene: view.window?.windowScene
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = gradientBackgroundView.bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyGradientColors()
    }

    private func installGradientBackground() {
        gradientBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        gradientBackgroundView.isUserInteractionEnabled = false
        gradientLayer.locations = [0, 1]
        applyGradientColors()
        gradientBackgroundView.layer.insertSublayer(gradientLayer, at: 0)
        view.insertSubview(gradientBackgroundView, at: 0)

        NSLayoutConstraint.activate([
            gradientBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func applyGradientColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        gradientLayer.colors = isDark
            ? [
                UIColor(red: 0.18, green: 0.16, blue: 0.10, alpha: 1).cgColor,
                UIColor.systemGroupedBackground.cgColor,
            ]
            : [
                UIColor(red: 1.0, green: 0.98, blue: 0.90, alpha: 1).cgColor,
                UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1).cgColor,
            ]
    }

    private func buildUI() {
        characterFan.configure(glyphs: glyphs)
        characterFan.translatesAutoresizingMaskIntoConstraints = false

        comboBadge.prepareForCascadeEntry()
        praiseBadge.prepareForCascadeEntry()

        let badgeStack = UIStackView(arrangedSubviews: [comboBadge, praiseBadge])
        badgeStack.axis = .vertical
        badgeStack.spacing = 14
        badgeStack.alignment = .center

        let centerStack = UIStackView(arrangedSubviews: [characterFan, badgeStack])
        centerStack.axis = .vertical
        centerStack.spacing = 32
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(centerStack)

        let centerY = centerStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -12)
        centerY.priority = .defaultHigh

        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            centerY,
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 28),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -28),

            characterFan.widthAnchor.constraint(equalToConstant: EncouragementCharacterFanView.preferredWidth),
            characterFan.heightAnchor.constraint(equalToConstant: EncouragementCharacterFanView.preferredHeight),
        ])

        configureCTA(.next(), target: self, action: #selector(nextTapped))
    }

    private func playCascadeBadgeAnimations() {
        UIView.animate(
            withDuration: 0.48,
            delay: 0.12,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.45,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.comboBadge.alpha = 1
                self.comboBadge.transform = .identity
            },
            completion: { _ in
                self.comboBadge.playEntryShimmer()
            }
        )

        UIView.animate(
            withDuration: 0.48,
            delay: 0.34,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.45,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.praiseBadge.alpha = 1
                self.praiseBadge.transform = .identity
            },
            completion: { _ in
                self.praiseBadge.playEntryShimmer()
            }
        )
    }

    @objc private func nextTapped() {
        progressiveContainerCoordinator?.dismissNotchDropIfNeeded()
        progressiveContainerCoordinator?.setLessonHeaderHidden(false, animated: true)
        advanceToNextStep()
    }
}

// MARK: - Character fan

private final class EncouragementCharacterFanView: UIView {

    static let preferredWidth: CGFloat = 280
    static let preferredHeight: CGFloat = 160
    private static let cardWidth: CGFloat = 120
    private static let cardHorizontalOffset: CGFloat = 52

    private var cards: [KanaCard] = []

    func configure(glyphs: [(kana: String, romaji: String)]) {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()

        let displayGlyphs = Array(glyphs.prefix(2))
        for (index, glyph) in displayGlyphs.enumerated() {
            let card = KanaCard()
            card.translatesAutoresizingMaskIntoConstraints = false
            card.setPresentation(.detailHero)
            card.setAccess(.reference)
            card.configure(kana: glyph.kana, romaji: glyph.romaji)
            applyEncouragementBorder(to: card)
            addSubview(card)
            cards.append(card)

            let rotation = index == 0 ? CGAffineTransform(rotationAngle: -.pi / 30) : CGAffineTransform(rotationAngle: .pi / 30)
            card.transform = rotation.scaledBy(x: 0.88, y: 0.88)
            card.alpha = 0

            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: Self.cardWidth),
                card.centerYAnchor.constraint(
                    equalTo: centerYAnchor,
                    constant: index == 0 ? -4 : 4
                ),
                card.centerXAnchor.constraint(
                    equalTo: centerXAnchor,
                    constant: index == 0 ? -Self.cardHorizontalOffset : Self.cardHorizontalOffset
                ),
            ])
        }
    }

    func playEntryAnimation() {
        for (index, card) in cards.enumerated() {
            let rotation = index == 0 ? CGAffineTransform(rotationAngle: -.pi / 30) : CGAffineTransform(rotationAngle: .pi / 30)
            UIView.animate(
                withDuration: 0.52,
                delay: Double(index) * 0.08,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.45,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    card.alpha = 1
                    card.transform = rotation
                }
            )
        }
    }

    private func applyEncouragementBorder(to card: KanaCard) {
        card.layer.borderWidth = 2
        card.layer.borderColor = ExperimentPalette.highlightBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        for card in cards {
            applyEncouragementBorder(to: card)
        }
    }
}
