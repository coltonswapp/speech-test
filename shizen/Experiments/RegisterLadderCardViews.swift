//
//  RegisterLadderCardViews.swift
//  shizen
//
//  Card faces for the register-ladder pager: English hook, three register
//  slides, then a why close. Hero cards sit on the true center; title blocks
//  center in the remaining space above. Built for live display and export.
//

import UIKit

// MARK: - Layout constants

private enum RegisterLadderCardMetrics {
    /// Inner padding inside hero cards.
    static let heroInset: CGFloat = 22
    static let sideInset: CGFloat = 28
    static let topBleed: CGFloat = 24
    static let headerToCardGap: CGFloat = 28
    static let heroWidth: CGFloat = 300
    static let hookHeroWidth: CGFloat = 280

    static let hookCardFont = UIFontMetrics(forTextStyle: .title2)
        .scaledFont(for: .systemFont(ofSize: 22, weight: .semibold))
    static let japaneseCardFont = UIFontMetrics(forTextStyle: .title2)
        .scaledFont(for: .systemFont(ofSize: 24, weight: .semibold))
    static let whyCardFont = UIFontMetrics(forTextStyle: .body)
        .scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
}

// MARK: - Shared hero card chrome

private final class RegisterLadderHeroCard: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        clipsToBounds = false
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        applyBorderColor()
        applyShadowOpacity()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
        applyShadowOpacity()
        setNeedsLayout()
    }

    private func applyBorderColor() {
        layer.borderColor = ExperimentPalette.cardBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    private func applyShadowOpacity() {
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
    }
}

// MARK: - Shared helpers

private func installRegisterLadderWatermark(in host: UIView) {
    let label = UILabel()
    label.text = "shizenapp.com"
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = UIColor.secondaryLabel.withAlphaComponent(0.65)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14),
    ])
}

/// Eyebrow + title stacked, pinned toward the bottom of the band above `hero`
/// so the header sits closer to the card.
private func installRegisterLadderHeader(
    eyebrow: UILabel,
    title: UILabel,
    in host: UIView,
    above hero: UIView
) -> UIStackView {
    let header = UIStackView(arrangedSubviews: [eyebrow, title])
    header.axis = .vertical
    header.alignment = .fill
    header.spacing = 10
    header.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(header)

    NSLayoutConstraint.activate([
        header.leadingAnchor.constraint(
            equalTo: host.leadingAnchor,
            constant: RegisterLadderCardMetrics.sideInset
        ),
        header.trailingAnchor.constraint(
            equalTo: host.trailingAnchor,
            constant: -RegisterLadderCardMetrics.sideInset
        ),
        header.bottomAnchor.constraint(
            equalTo: hero.topAnchor,
            constant: -RegisterLadderCardMetrics.headerToCardGap
        ),
        header.topAnchor.constraint(
            greaterThanOrEqualTo: host.topAnchor,
            constant: RegisterLadderCardMetrics.topBleed
        ),
    ])

    return header
}

private func pinHeroContent(
    _ content: UIView,
    in hero: UIView,
    inset: CGFloat = RegisterLadderCardMetrics.heroInset
) {
    content.translatesAutoresizingMaskIntoConstraints = false
    hero.addSubview(content)
    content.setContentHuggingPriority(.required, for: .vertical)
    content.setContentCompressionResistancePriority(.required, for: .vertical)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: hero.topAnchor, constant: inset),
        content.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -inset),
        content.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: inset),
        content.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -inset),
    ])
}

private func centeredAttributedJapanese(_ text: String, font: UIFont) -> NSAttributedString {
    let base = JapaneseFuriganaBuilder.attributedString(
        for: text,
        font: font,
        textColor: .label
    )
    let centered = NSMutableAttributedString(attributedString: base)
    guard centered.length > 0 else { return centered }
    let range = NSRange(location: 0, length: centered.length)
    let existing = (centered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        ?? NSParagraphStyle.default
    let paragraph = (existing.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    paragraph.alignment = .center
    centered.addAttribute(.paragraphStyle, value: paragraph, range: range)
    return centered
}

// MARK: - Slide 1: Hook / ask

final class RegisterLadderHookCardView: UIView {
    private let eyebrowLabel = UILabel()
    private let questionLabel = UILabel()
    private let heroCard = RegisterLadderHeroCard()
    private let heroEnglishLabel = UILabel()
    private let formatLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        eyebrowLabel.font = .preferredFont(forTextStyle: .subheadline)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.numberOfLines = 0
        eyebrowLabel.text = "One sentence, three ways"

        questionLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        questionLabel.textColor = .label
        questionLabel.textAlignment = .center
        questionLabel.numberOfLines = 0
        questionLabel.text = "How do you say this in Japanese?"

        heroEnglishLabel.font = RegisterLadderCardMetrics.hookCardFont
        heroEnglishLabel.textColor = .label
        heroEnglishLabel.textAlignment = .center
        heroEnglishLabel.numberOfLines = 0

        formatLabel.font = .preferredFont(forTextStyle: .footnote)
        formatLabel.textColor = .tertiaryLabel
        formatLabel.textAlignment = .center
        formatLabel.numberOfLines = 1
        formatLabel.text = "casual → polite → keigo"
        formatLabel.translatesAutoresizingMaskIntoConstraints = false

        heroCard.translatesAutoresizingMaskIntoConstraints = false
        pinHeroContent(heroEnglishLabel, in: heroCard)

        addSubview(heroCard)
        addSubview(formatLabel)
        _ = installRegisterLadderHeader(
            eyebrow: eyebrowLabel,
            title: questionLabel,
            in: self,
            above: heroCard
        )
        installRegisterLadderWatermark(in: self)

        NSLayoutConstraint.activate([
            heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            heroCard.widthAnchor.constraint(equalToConstant: RegisterLadderCardMetrics.hookHeroWidth),

            formatLabel.topAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: 14),
            formatLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: RegisterLadderCardMetrics.sideInset
            ),
            formatLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -RegisterLadderCardMetrics.sideInset
            ),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = max(0, bounds.width - RegisterLadderCardMetrics.sideInset * 2)
        eyebrowLabel.preferredMaxLayoutWidth = maxWidth
        questionLabel.preferredMaxLayoutWidth = maxWidth
        formatLabel.preferredMaxLayoutWidth = maxWidth
        heroEnglishLabel.preferredMaxLayoutWidth = max(
            0,
            RegisterLadderCardMetrics.hookHeroWidth - RegisterLadderCardMetrics.heroInset * 2
        )
    }

    func configure(english: String) {
        heroEnglishLabel.text = english
        setNeedsLayout()
    }
}

// MARK: - Slides 2–4: Register levels

final class RegisterLadderLevelCardView: UIView {
    let register: RegisterLadderDeck.Register

    private let eyebrowLabel = UILabel()
    private let registerTitleLabel = UILabel()
    private let heroCard = RegisterLadderHeroCard()
    private let japaneseLabel = FuriganaTranscriptLabel()
    private let audienceLabel = UILabel()

    var japaneseHitView: UIView { heroCard }

    override init(frame: CGRect) {
        self.register = .casual
        super.init(frame: frame)
        setup()
    }

    init(register: RegisterLadderDeck.Register) {
        self.register = register
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.register = .casual
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        eyebrowLabel.font = .preferredFont(forTextStyle: .subheadline)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.numberOfLines = 0
        eyebrowLabel.text = "Register ladder"

        registerTitleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        registerTitleLabel.textColor = .label
        registerTitleLabel.textAlignment = .center
        registerTitleLabel.numberOfLines = 1
        registerTitleLabel.text = register.title

        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.lineBreakMode = .byWordWrapping
        japaneseLabel.textAlignment = .center
        japaneseLabel.font = RegisterLadderCardMetrics.japaneseCardFont
        japaneseLabel.textColor = .label
        japaneseLabel.isUserInteractionEnabled = false

        audienceLabel.font = .preferredFont(forTextStyle: .footnote)
        audienceLabel.textColor = .tertiaryLabel
        audienceLabel.textAlignment = .center
        audienceLabel.numberOfLines = 1
        audienceLabel.translatesAutoresizingMaskIntoConstraints = false

        heroCard.translatesAutoresizingMaskIntoConstraints = false
        pinHeroContent(japaneseLabel, in: heroCard)

        addSubview(heroCard)
        addSubview(audienceLabel)
        _ = installRegisterLadderHeader(
            eyebrow: eyebrowLabel,
            title: registerTitleLabel,
            in: self,
            above: heroCard
        )
        installRegisterLadderWatermark(in: self)

        NSLayoutConstraint.activate([
            heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            heroCard.widthAnchor.constraint(equalToConstant: RegisterLadderCardMetrics.heroWidth),

            audienceLabel.topAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: 14),
            audienceLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: RegisterLadderCardMetrics.sideInset
            ),
            audienceLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -RegisterLadderCardMetrics.sideInset
            ),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = max(0, bounds.width - RegisterLadderCardMetrics.sideInset * 2)
        eyebrowLabel.preferredMaxLayoutWidth = maxWidth
        registerTitleLabel.preferredMaxLayoutWidth = maxWidth
        audienceLabel.preferredMaxLayoutWidth = maxWidth
        japaneseLabel.preferredMaxLayoutWidth = max(
            0,
            RegisterLadderCardMetrics.heroWidth - RegisterLadderCardMetrics.heroInset * 2
        )
    }

    func configure(level: RegisterLadderLevel) {
        applyJapanese(level.japanese)
        audienceLabel.text = level.audience
    }

    func applyJapanese(_ text: String) {
        let font = RegisterLadderCardMetrics.japaneseCardFont
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: centeredAttributedJapanese(text, font: font),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font),
                left: 0,
                bottom: 2,
                right: 0
            )
        )
        japaneseLabel.textAlignment = .center
        setNeedsLayout()
    }

    func japaneseContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        heroCard.convert(heroCard.bounds, to: coordinateSpace)
            .insetBy(dx: -8, dy: -8)
            .contains(point)
    }
}

// MARK: - Slide 5: Why

final class RegisterLadderWhyCardView: UIView {
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let whyLabel = UILabel()
    private let heroCard = RegisterLadderHeroCard()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        eyebrowLabel.font = .preferredFont(forTextStyle: .subheadline)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.numberOfLines = 0
        eyebrowLabel.text = "What actually changes"

        titleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = "Same idea. Different endings."

        whyLabel.font = RegisterLadderCardMetrics.whyCardFont
        whyLabel.textColor = .label
        whyLabel.textAlignment = .center
        whyLabel.numberOfLines = 0

        heroCard.translatesAutoresizingMaskIntoConstraints = false
        pinHeroContent(whyLabel, in: heroCard)

        addSubview(heroCard)
        _ = installRegisterLadderHeader(
            eyebrow: eyebrowLabel,
            title: titleLabel,
            in: self,
            above: heroCard
        )
        installRegisterLadderWatermark(in: self)

        NSLayoutConstraint.activate([
            heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            heroCard.widthAnchor.constraint(equalToConstant: RegisterLadderCardMetrics.heroWidth),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = max(0, bounds.width - RegisterLadderCardMetrics.sideInset * 2)
        eyebrowLabel.preferredMaxLayoutWidth = maxWidth
        titleLabel.preferredMaxLayoutWidth = maxWidth
        whyLabel.preferredMaxLayoutWidth = max(
            0,
            RegisterLadderCardMetrics.heroWidth - RegisterLadderCardMetrics.heroInset * 2
        )
    }

    func configure(why: String) {
        whyLabel.text = why
        setNeedsLayout()
    }
}
