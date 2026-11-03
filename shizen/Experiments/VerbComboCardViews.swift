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
    private let heroCard = SlideHeroCardView()
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
        SlideJapaneseText.apply(hookVerb, to: verbLabel, font: .systemFont(ofSize: 40, weight: .bold))
        setNeedsLayout()
    }
}

// MARK: - Still 2

final class VerbComboRuleCardView: UIView {
    private let heroCard = SlideHeroCardView()
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
    private let heroCard = SlideHeroCardView()
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
        SlideJapaneseText.apply(
            example.compound,
            to: compoundLabel,
            font: .systemFont(ofSize: 32, weight: .bold)
        )
        SlideJapaneseText.apply(
            example.exampleLine,
            to: exampleLabel,
            font: .systemFont(ofSize: 22, weight: .semibold)
        )
        englishLabel.text = example.exampleEnglish
        setNeedsLayout()
    }
}
