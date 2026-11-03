//
//  PaywallBoldHeroGlassViewController.swift
//  shizen
//
//  Variant: Bold hero, glass edition. The huge, tightly leaded headline and faint grid over
//  the drifting brand-yellow blobs, the swipeable glass feature cards, and the feature
//  carousel's pinned footer with shorter plan tiles ("$59.99/yr") above the brand yellow CTA.
//  `.compact` swaps the three-line headline for a smaller one-sentence title and subhead.
//  `showsColorBlobs: false` keeps the grid on a plain page, with no colored backdrop.
//

import UIKit

final class PaywallBoldHeroGlassViewController: PaywallBaseViewController {
    enum Headline {
        /// Three huge, tightly leaded lines.
        case hero
        /// One smaller sentence that wraps naturally.
        case compact
    }

    private static let page = paywallDynamicColor(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.04, alpha: 1)
    )

    private let backdrop: BrandBlobBackdrop?
    private let carousel = PaywallFeatureCarouselView()
    private var tiles: [PaywallPlanTile] = []
    private let finePrint = UILabel()
    private let headlineStyle: Headline

    init(provider: PaywallProviding, headline: Headline = .hero, showsColorBlobs: Bool = true) {
        headlineStyle = headline
        backdrop = showsColorBlobs ? BrandBlobBackdrop() : nil
        super.init(provider: provider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        // The warm page color is there to sit under the blobs. Without them, the page is plain.
        view.backgroundColor = backdrop == nil ? .systemBackground : Self.page
        backdrop?.translatesAutoresizingMaskIntoConstraints = false
        if let backdrop { view.addSubview(backdrop) }
        let grid = PaywallGridView()
        grid.lineColor = UIColor.label.withAlphaComponent(0.06)
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        for layer in [backdrop, grid].compactMap({ $0 }) {
            NSLayoutConstraint.activate([
                layer.topAnchor.constraint(equalTo: view.topAnchor),
                layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        backdrop?.startDrifting()
        carousel.startAutoAdvance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        carousel.stopAutoAdvance()
    }

    override func render(_ offering: PaywallOffering) {
        let headline = makeHeadline(offering)

        let subhead = UILabel()
        subhead.text = offering.string("subtitle", default: "Real conversations, real voices: Japanese the way it's actually spoken.")
        subhead.font = .systemFont(ofSize: headlineStyle == .hero ? 20 : 17, weight: .semibold)
        subhead.textColor = .label
        subhead.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [headline, subhead, carousel])
        content.axis = .vertical
        content.spacing = 14
        content.setCustomSpacing(24, after: subhead)

        // Footer: the feature carousel's, with shorter tiles.
        tiles = makePaywallPlanTiles(for: offering, compact: true, inlineUnit: true)
        bind(tiles)
        let plans = makePaywallPlanTileRow(tiles)
        // Room for the SAVE badge that straddles the tiles' top edge.
        plans.isLayoutMarginsRelativeArrangement = true
        plans.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)

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
        tiles.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? "Try free & subscribe" : "Continue"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
    }

    /// Title text with its accent in the selected-token pill from sentence scrub.
    private func makeHeadline(_ offering: PaywallOffering) -> UILabel {
        let headline = UILabel()
        headline.numberOfLines = 0
        let font: UIFont
        let text: NSMutableAttributedString
        let accent: String
        switch headlineStyle {
        case .hero:
            // Tight leading so the three big lines read as one block.
            let leading = NSMutableParagraphStyle()
            leading.lineHeightMultiple = 0.8
            font = .systemFont(ofSize: 50, weight: .heavy)
            text = NSMutableAttributedString(
                string: offering.string("title", default: "Hear\nJapanese\n"),
                attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: leading]
            )
            accent = offering.string("titleAccent", default: "for real")
            headline.adjustsFontSizeToFitWidth = true
            headline.minimumScaleFactor = 0.6
        case .compact:
            font = .systemFont(ofSize: 34, weight: .heavy)
            text = NSMutableAttributedString(
                string: offering.string("title", default: "Immerse yourself in "),
                attributes: [.font: font, .foregroundColor: UIColor.label]
            )
            accent = offering.string("titleAccent", default: "conversation")
        }
        // The pill keeps normal leading so it clears the descenders above it.
        let pill = NSMutableAttributedString(attributedString: makePaywallTokenHighlight(accent, font: font, traitCollection: traitCollection))
        pill.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: NSRange(location: 0, length: pill.length))
        text.append(pill)
        headline.attributedText = text
        headline.accessibilityLabel = text.string.replacingOccurrences(of: "\u{FFFC}", with: accent)
        return headline
    }
}
