//
//  PaywallHanaViewController.swift
//  shizen
//
//  Variant: Hana pitches Pro in a speech bubble, then a tiled feature list, with short
//  side-by-side plan tiles pinned above the CTA (Locket / Raycast feel). Warm cream page,
//  adapts to dark.
//

import UIKit

final class PaywallHanaViewController: PaywallBaseViewController {
    private static let page = paywallDynamicColor(light: UIColor(red: 1, green: 0.976, blue: 0.93, alpha: 1), dark: UIColor(red: 0.09, green: 0.08, blue: 0.06, alpha: 1))
    private static let card = paywallDynamicColor(light: .white, dark: UIColor(white: 1, alpha: 0.07))
    private static let accent = UIColor(red: 1, green: 0.78, blue: 0.05, alpha: 1)
    private static let accentInk = UIColor(red: 0.2, green: 0.14, blue: 0, alpha: 1)

    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 112, height: 112))
    private var tiles: [PaywallPlanTile] = []
    private let finePrint = UILabel()

    override func viewDidLoad() {
        view.backgroundColor = Self.page
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mascot.play(.excited)
    }

    override func render(_ offering: PaywallOffering) {
        mascot.translatesAutoresizingMaskIntoConstraints = false
        mascot.set(MascotPreset.happy.expression, animated: false)
        let mascotHolder = UIView()
        mascotHolder.addSubview(mascot)
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: 112),
            mascot.heightAnchor.constraint(equalToConstant: 112),
            mascot.topAnchor.constraint(equalTo: mascotHolder.topAnchor),
            mascot.bottomAnchor.constraint(equalTo: mascotHolder.bottomAnchor),
            mascot.centerXAnchor.constraint(equalTo: mascotHolder.centerXAnchor),
        ])

        let bubble = makeBubble(offering.string(
            "hana_line",
            default: "You've got the ear for it. Let's keep you talking every day."
        ))

        let title = UILabel()
        title.text = offering.string("title", default: "Shizen Pro")
        title.font = .systemFont(ofSize: 32, weight: .heavy)
        title.textAlignment = .center

        let featureCard = UIStackView(arrangedSubviews: PaywallCopy.features.map {
            makePaywallFeatureRow($0, style: .tile)
        })
        featureCard.axis = .vertical
        featureCard.spacing = 18
        featureCard.isLayoutMarginsRelativeArrangement = true
        featureCard.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18)
        featureCard.backgroundColor = Self.card
        featureCard.layer.cornerRadius = 24
        featureCard.layer.cornerCurve = .continuous

        tiles = makePaywallPlanTiles(for: offering, compact: true, inlineUnit: true, accent: Self.accent, badgeText: Self.accentInk)
        bind(tiles)
        let plans = makePaywallPlanTileRow(tiles)
        // Room for the SAVE badge that straddles the tiles' top edge.
        plans.isLayoutMarginsRelativeArrangement = true
        plans.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)

        let content = UIStackView(arrangedSubviews: [mascotHolder, bubble, title, featureCard])
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 20
        content.setCustomSpacing(10, after: mascotHolder)
        content.setCustomSpacing(16, after: bubble)

        let cta = makeCTA(background: Self.accent, foreground: Self.accentInk)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = .secondaryLabel
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0

        var noThanksConfig = UIButton.Configuration.plain()
        noThanksConfig.title = "Maybe later"
        noThanksConfig.baseForegroundColor = .secondaryLabel
        let noThanks = UIButton(configuration: noThanksConfig)
        noThanks.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [plans, cta, finePrint, noThanks])
        footer.axis = .vertical
        footer.spacing = 8
        footer.setCustomSpacing(14, after: plans)
        footer.setCustomSpacing(4, after: finePrint)

        installScrollLayout(content: content, footer: footer, topInset: 56)
        installTopBar(tint: .label)
    }

    override func selectedPackageDidChange(animated: Bool) {
        tiles.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = PaywallCopy.ctaTitle(for: selectedPackage)
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
        if animated { mascot.play(selectedPackage?.period == .annual ? .excited : .pleased) }
    }

    private func makeBubble(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let bubble = UIView()
        bubble.backgroundColor = Self.card
        bubble.layer.cornerRadius = 22
        bubble.layer.cornerCurve = .continuous
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -18),
        ])
        return bubble
    }
}
