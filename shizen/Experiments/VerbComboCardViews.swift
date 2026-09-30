//
//  VerbComboCardViews.swift
//  shizen
//
//  Five stills for one added verb. The hero card is pinned to the true center
//  of the slide. On example stills that card is the sentence. Ruby is part of
//  the label's layout height so furigana does not shove the card off center.
//

import UIKit

private enum VerbComboCardMetrics {
    static let sideInset: CGFloat = 28
    static let heroInset: CGFloat = 22
    static let heroWidth: CGFloat = 300
    static let headerGap: CGFloat = 28
}

private final class VerbComboHeroCard: UIView {
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
    }

    private func applyBorderColor() {
        layer.borderColor = ExperimentPalette.cardBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    private func applyShadowOpacity() {
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
    }
}

private func verbComboTextHasKanji(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
}

private func verbComboCenteredJapanese(_ text: String, font: UIFont) -> NSAttributedString {
    let base = JapaneseFuriganaBuilder.attributedString(for: text, font: font, textColor: .label)
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

private func verbComboApplyJapanese(
    _ text: String,
    to label: FuriganaTranscriptLabel,
    font: UIFont
) {
    label.numberOfLines = 0
    label.textAlignment = .center
    label.lineBreakMode = .byWordWrapping
    // Ruby height stays inside the label. Leaving this on reports the ruby
    // inset twice, so Auto Layout centers the glyphs below the card.
    label.verticalTextInsetsAffectAlignmentRect = false
    if verbComboTextHasKanji(text) {
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: label,
            attributed: verbComboCenteredJapanese(text, font: font),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font),
                left: 0,
                bottom: 2,
                right: 0
            )
        )
    } else {
        label.textInsets = .zero
        label.attributedText = nil
        label.font = font
        label.text = text
        label.textColor = .label
    }
    label.textAlignment = .center
}

private func verbComboPinHero(_ hero: UIView, in host: UIView) {
    hero.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(hero)
    NSLayoutConstraint.activate([
        hero.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        hero.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        hero.widthAnchor.constraint(equalToConstant: VerbComboCardMetrics.heroWidth),
    ])
}

private func verbComboPinContent(_ content: UIView, in hero: UIView) {
    content.translatesAutoresizingMaskIntoConstraints = false
    content.setContentHuggingPriority(.required, for: .vertical)
    content.setContentCompressionResistancePriority(.required, for: .vertical)
    hero.addSubview(content)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: hero.topAnchor, constant: VerbComboCardMetrics.heroInset),
        content.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -VerbComboCardMetrics.heroInset),
        content.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: VerbComboCardMetrics.heroInset),
        content.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -VerbComboCardMetrics.heroInset),
    ])
}

/// Header sits in the band above a centered hero, close to the card.
private func verbComboPinHeader(_ header: UIView, above hero: UIView, in host: UIView) {
    header.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(header)
    NSLayoutConstraint.activate([
        header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: VerbComboCardMetrics.sideInset),
        header.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -VerbComboCardMetrics.sideInset),
        header.bottomAnchor.constraint(equalTo: hero.topAnchor, constant: -VerbComboCardMetrics.headerGap),
        header.topAnchor.constraint(greaterThanOrEqualTo: host.topAnchor, constant: 24),
    ])
}

// MARK: - Still 1

final class VerbComboHookCardView: UIView {
    private let questionLabel = UILabel()
    private let heroCard = VerbComboHeroCard()
    private let verbLabel = FuriganaTranscriptLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        questionLabel.font = .systemFont(ofSize: 22, weight: .bold)
        questionLabel.textColor = .label
        questionLabel.textAlignment = .center
        questionLabel.numberOfLines = 0
        questionLabel.text = VerbComboCopy.question

        verbComboPinContent(verbLabel, in: heroCard)
        verbComboPinHero(heroCard, in: self)
        verbComboPinHeader(questionLabel, above: heroCard, in: self)
        ExperimentSlideWatermark.install(in: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerWidth = max(0, bounds.width - VerbComboCardMetrics.sideInset * 2)
        questionLabel.preferredMaxLayoutWidth = headerWidth
        verbLabel.preferredMaxLayoutWidth = VerbComboCardMetrics.heroWidth - VerbComboCardMetrics.heroInset * 2
    }

    func configure(hookVerb: String) {
        verbComboApplyJapanese(hookVerb, to: verbLabel, font: .systemFont(ofSize: 40, weight: .bold))
        setNeedsLayout()
    }
}

// MARK: - Still 2

final class VerbComboRuleCardView: UIView {
    private let heroCard = VerbComboHeroCard()
    private let ruleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        ruleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        ruleLabel.textColor = .label
        ruleLabel.textAlignment = .center
        ruleLabel.numberOfLines = 0

        verbComboPinContent(ruleLabel, in: heroCard)
        verbComboPinHero(heroCard, in: self)
        ExperimentSlideWatermark.install(in: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ruleLabel.preferredMaxLayoutWidth = VerbComboCardMetrics.heroWidth - VerbComboCardMetrics.heroInset * 2
    }

    func configure(rule: String) {
        ruleLabel.text = rule
        setNeedsLayout()
    }
}

// MARK: - Stills 3–5

final class VerbComboExampleCardView: UIView {
    private let compoundLabel = FuriganaTranscriptLabel()
    private let heroCard = VerbComboHeroCard()
    private let exampleLabel = FuriganaTranscriptLabel()
    private let englishLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ExperimentPalette.pageBackground
        clipsToBounds = true

        compoundLabel.textAlignment = .center

        englishLabel.font = .systemFont(ofSize: 16, weight: .medium)
        englishLabel.textColor = .secondaryLabel
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 2
        englishLabel.translatesAutoresizingMaskIntoConstraints = false

        verbComboPinContent(exampleLabel, in: heroCard)
        verbComboPinHero(heroCard, in: self)
        verbComboPinHeader(compoundLabel, above: heroCard, in: self)
        addSubview(englishLabel)
        ExperimentSlideWatermark.install(in: self)

        NSLayoutConstraint.activate([
            englishLabel.topAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: 14),
            englishLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: VerbComboCardMetrics.sideInset),
            englishLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -VerbComboCardMetrics.sideInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerWidth = max(0, bounds.width - VerbComboCardMetrics.sideInset * 2)
        compoundLabel.preferredMaxLayoutWidth = headerWidth
        exampleLabel.preferredMaxLayoutWidth = VerbComboCardMetrics.heroWidth - VerbComboCardMetrics.heroInset * 2
        englishLabel.preferredMaxLayoutWidth = headerWidth
    }

    func configure(example: VerbComboExample) {
        verbComboApplyJapanese(
            example.compound,
            to: compoundLabel,
            font: .systemFont(ofSize: 32, weight: .bold)
        )
        verbComboApplyJapanese(
            example.exampleLine,
            to: exampleLabel,
            font: .systemFont(ofSize: 22, weight: .semibold)
        )
        englishLabel.text = example.exampleEnglish
        setNeedsLayout()
    }
}
