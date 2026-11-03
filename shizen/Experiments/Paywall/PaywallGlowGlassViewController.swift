//
//  PaywallGlowGlassViewController.swift
//  shizen
//
//  Variant: Night glow's short pitch, glass edition. Hana centered over the drifting
//  brand-yellow blobs, a title-only feature list in one glass card, and short side-by-side
//  glass plan tiles with per-week pricing pinned above the brand yellow CTA. No free-trial switch.
//

import UIKit

final class PaywallGlowGlassViewController: PaywallBaseViewController {
    private static let page = paywallDynamicColor(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.04, alpha: 1)
    )

    private let backdrop = BrandBlobBackdrop()
    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 96, height: 96))
    private var rows: [PaywallPlanTile] = []
    private let finePrint = UILabel()

    override func viewDidLoad() {
        view.backgroundColor = Self.page
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        backdrop.startDrifting()
        mascot.play(.excited)
    }

    override func render(_ offering: PaywallOffering) {
        mascot.translatesAutoresizingMaskIntoConstraints = false
        // Basic pink like onboarding and Profile, regardless of the user's saved theme.
        mascot.setTheme(.pink, animated: false)
        mascot.set(MascotPreset.happy.expression, animated: false)
        let mascotHolder = UIView()
        mascotHolder.addSubview(mascot)
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: 96),
            mascot.heightAnchor.constraint(equalToConstant: 96),
            mascot.topAnchor.constraint(equalTo: mascotHolder.topAnchor),
            mascot.bottomAnchor.constraint(equalTo: mascotHolder.bottomAnchor),
            mascot.centerXAnchor.constraint(equalTo: mascotHolder.centerXAnchor),
        ])

        let title = UILabel()
        title.text = offering.string("title", default: "Unlock your\nJapanese tutor today")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 0

        rows = makePaywallPlanTiles(for: offering, compact: true, inlineUnit: true)
        bind(rows)
        let plans = makePaywallPlanTileRow(rows)
        // Room for the SAVE badge that straddles the tiles' top edge.
        plans.isLayoutMarginsRelativeArrangement = true
        plans.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)

        let content = UIStackView(arrangedSubviews: [mascotHolder, title, makeFeatureCard()])
        content.axis = .vertical
        content.spacing = 22
        content.setCustomSpacing(12, after: mascotHolder)

        let cta = makeCTA(background: Colors.ctaYellow, foreground: Colors.ctaDarkYellow)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = .secondaryLabel
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0
        let links = makeLegalLinks(color: .secondaryLabel, includesRestore: true)
        let linksRow = UIStackView(arrangedSubviews: [links])
        linksRow.alignment = .center
        linksRow.axis = .vertical

        let footer = UIStackView(arrangedSubviews: [plans, cta, finePrint, linksRow])
        footer.axis = .vertical
        footer.spacing = 10
        footer.setCustomSpacing(14, after: plans)

        installScrollLayout(content: content, footer: footer, horizontalInset: 20, topInset: 64)
        installTopBar(tint: .label, showsRestore: false)
    }

    override func selectedPackageDidChange(animated: Bool) {
        rows.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? "Try free & subscribe" : "Continue"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
        if animated { mascot.play(selectedPackage?.period == .annual ? .excited : .curious) }
    }

    /// Night glow's plain, title-only feature list, held in a single glass card.
    private func makeFeatureCard() -> UIView {
        let list = UIStackView(arrangedSubviews: PaywallCopy.features.map {
            makePaywallFeatureRow($0, style: .plain, titleColor: .label, showsDetail: false)
        })
        list.axis = .vertical
        list.spacing = 14
        list.translatesAutoresizingMaskIntoConstraints = false

        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glass.cornerConfiguration = .corners(radius: .fixed(24))
        glass.contentView.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 18),
            list.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 18),
            list.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -18),
            list.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -18),
        ])
        return glass
    }
}
