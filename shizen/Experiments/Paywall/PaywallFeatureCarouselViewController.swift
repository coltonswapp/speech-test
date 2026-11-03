//
//  PaywallFeatureCarouselViewController.swift
//  shizen
//
//  Variant: swipe through glass feature cards over the brand blobs. Each card shows a
//  small preview of the feature (lesson thumbnails, a casual line in the lesson glass bubble, a
//  word insight, a quiz, a saved flashcard), all from one train-station scene so they
//  read as one story. Cards auto-advance until the user swipes; Hana reacts to each page.
//  Short side-by-side glass plan tiles ("$59.99/yr") sit in the pinned footer above the brand yellow CTA.
//

import UIKit

final class PaywallFeatureCarouselViewController: PaywallBaseViewController {
    private static let page = paywallDynamicColor(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.04, alpha: 1)
    )

    private let backdrop = BrandBlobBackdrop()
    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
    private let carousel = PaywallFeatureCarouselView()
    private var tiles: [PaywallPlanTile] = []
    private let finePrint = UILabel()

    private var carouselAnalytics = PaywallCarouselAnalytics()

    override var analyticsVariant: String? { "feature_carousel" }
    override var analyticsExtraProperties: [String: Any] { carouselAnalytics.summary }

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
        carouselAnalytics.appeared()
        backdrop.startDrifting()
        mascot.play(.excited)
        carousel.startAutoAdvance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        carousel.stopAutoAdvance()
        carouselAnalytics.disappeared()
    }

    override func render(_ offering: PaywallOffering) {
        mascot.translatesAutoresizingMaskIntoConstraints = false
        // Basic pink like onboarding and Profile, regardless of the user's saved theme.
        mascot.setTheme(.pink, animated: false)
        mascot.set(MascotPreset.happy.expression, animated: false)
        let mascotHolder = UIView()
        mascotHolder.addSubview(mascot)
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: 72),
            mascot.heightAnchor.constraint(equalToConstant: 72),
            mascot.topAnchor.constraint(equalTo: mascotHolder.topAnchor),
            mascot.bottomAnchor.constraint(equalTo: mascotHolder.bottomAnchor),
            mascot.centerXAnchor.constraint(equalTo: mascotHolder.centerXAnchor),
        ])

        let title = UILabel()
        let titleText = NSMutableAttributedString(
            string: offering.string("title", default: "Hear Japanese the way it's really spoken with "),
            attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor.label]
        )
        // "Pro" in the selected-token pill from sentence scrub.
        titleText.append(makePaywallTokenHighlight("Pro", font: .systemFont(ofSize: 26, weight: .heavy), traitCollection: traitCollection))
        title.attributedText = titleText
        title.accessibilityLabel = titleText.string.replacingOccurrences(of: "\u{FFFC}", with: "Pro")
        title.textAlignment = .center
        title.numberOfLines = 0

        carousel.onPageChange = { [weak self] page, trigger in
            guard let self else { return }
            mascot.play(.pleased)
            if let properties = carouselAnalytics.pageChanged(to: page, trigger: trigger) {
                trackFunnel(.paywallCarouselSwiped, properties)
            }
        }

        tiles = makePaywallPlanTiles(for: offering, compact: true, inlineUnit: true)
        bind(tiles)
        let plans = makePaywallPlanTileRow(tiles)
        // Room for the SAVE badge that straddles the tiles' top edge.
        plans.isLayoutMarginsRelativeArrangement = true
        plans.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)

        let content = UIStackView(arrangedSubviews: [mascotHolder, title, carousel])
        content.axis = .vertical
        content.spacing = 20
        content.setCustomSpacing(10, after: mascotHolder)

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

        installScrollLayout(content: content, footer: footer, horizontalInset: 20, topInset: 60)
        // No nav title up here, so Hana sits just under the Dynamic Island instead of
        // below the full top safe area.
        scrollView.contentInsetAdjustmentBehavior = .never
        installTopBar(tint: .label, showsRestore: false)
    }

    override func selectedPackageDidChange(animated: Bool) {
        tiles.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? "Try free & subscribe" : "Continue"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
    }
}
