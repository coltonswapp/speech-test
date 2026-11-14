//
//  PaywallHanaNoteViewController.swift
//  shizen
//
//  Variant: Team Note and paywall as one scrolling experience. Hana says who we are and that
//  subscriptions keep the lights on, then the title, a title-only glass feature card, short plan
//  tiles, and the brand yellow CTA fade in below her lines in the same scroll view. Nothing is
//  pinned but the close button. Tapping skips ahead through her lines.
//  `.compactPlain` puts the same note on Bold hero glass compact's plain grid, with its
//  headline, subhead, and swipeable feature cards in place of the title and feature card.
//

import UIKit

final class PaywallHanaNoteViewController: PaywallBaseViewController {
    enum Style {
        case brandBlobs
        case compactPlain
    }

    private static let page = paywallDynamicColor(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.04, alpha: 1)
    )
    private static let noteLines = [
        "Before you go on, here's a little about us.",
        "We're a tiny team building the Japanese app we always wanted: real conversations, natural voices, and lessons that actually stick.",
        "No ads, and we never sell your data. Subscriptions are how we keep the lights on and keep making new dialogues every week.",
        "Here's what your support gets you.",
    ]
    /// Clears the close button, which floats over the scrolling content.
    private static let topBarHeight: CGFloat = 44
    /// How long the feature cards show before the plans and CTA, counted from when they start to appear.
    private static let pricingDelay: TimeInterval = 3.5

    private let style: Style
    private let backdrop: BrandBlobBackdrop?
    private let carousel: PaywallFeatureCarouselView?
    private let timeline = TutorTimeline()
    private var chat: TutorChatView?
    private var paywallSections: [UIView] = []
    /// Held back so the sections above get a few seconds alone first.
    private var pricingSections: [UIView] = []
    private var tiles: [PaywallPlanTile] = []
    private let finePrint = UILabel()
    private var didStartNote = false

    init(provider: PaywallProviding, style: Style = .brandBlobs) {
        self.style = style
        backdrop = style == .brandBlobs ? BrandBlobBackdrop() : nil
        carousel = style == .compactPlain ? PaywallFeatureCarouselView() : nil
        super.init(provider: provider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        // The warm page color is there to sit under the blobs. Without them, the page is plain.
        let layer: UIView
        if let backdrop {
            view.backgroundColor = Self.page
            layer = backdrop
        } else {
            view.backgroundColor = .systemBackground
            let grid = PaywallGridView()
            grid.lineColor = UIColor.label.withAlphaComponent(0.06)
            layer = grid
        }
        layer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.topAnchor.constraint(equalTo: view.topAnchor),
            layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        backdrop?.startDrifting()
        // Coming back to the screen. The first start waits for the cards' reveal.
        if carousel?.superview != nil {
            carousel?.startAutoAdvance()
        }
        startNoteIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        carousel?.stopAutoAdvance()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            timeline.cancelAll()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let scrollView = chat?.scrollContainer else { return }
        let top = view.safeAreaInsets.top + Self.topBarHeight
        if scrollView.contentInset.top != top {
            let wasAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top + 1
            scrollView.contentInset.top = top
            if wasAtTop {
                scrollView.contentOffset.y = -top
            }
        }
        scrollView.contentInset.bottom = view.safeAreaInsets.bottom + 8
    }

    override func render(_ offering: PaywallOffering) {
        // Always the moving mascot, like the Hana team note.
        let chat = TutorChatView(timeline: timeline, avatars: .mascot)
        chat.scrollContainer.topEdgeEffect.style = .soft
        chat.scrollContainer.topEdgeEffect.isHidden = false
        let skipTap = UITapGestureRecognizer(target: self, action: #selector(skipAhead))
        skipTap.cancelsTouchesInView = false
        chat.addGestureRecognizer(skipTap)
        view.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: view.topAnchor),
            chat.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.chat = chat

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

        let purchase = UIStackView(arrangedSubviews: [cta, finePrint, linksRow])
        purchase.axis = .vertical
        purchase.spacing = 10

        switch style {
        case .brandBlobs:
            paywallSections = [makeTitle(for: offering), makeFeatureCard(), plans, purchase]
        case .compactPlain:
            let sections: [UIView?] = [makeCompactHeading(for: offering), carousel]
            paywallSections = sections.compactMap { $0 }
            pricingSections = [plans, purchase]
        }

        installTopBar(tint: .label, showsRestore: false)
        startNoteIfReady()
    }

    override func selectedPackageDidChange(animated: Bool) {
        tiles.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? "Try free & subscribe" : "Continue"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
    }

    // MARK: Note

    /// The offering can load before or after the view appears; the note waits for both.
    private func startNoteIfReady() {
        guard !didStartNote, chat != nil, view.window != nil else { return }
        didStartNote = true
        timeline.after(0.35) { [weak self] in
            self?.playNote(Self.noteLines[...])
        }
    }

    /// One line at a time, with a beat to read the longer ones, then the paywall.
    private func playNote(_ lines: ArraySlice<String>) {
        guard let chat else { return }
        guard let line = lines.first else {
            chat.appendCustom(paywallSections, stagger: 0.3, scrollDuration: pricingSections.isEmpty ? 1.4 : 1)
            carousel?.startAutoAdvance()
            guard !pricingSections.isEmpty else { return }
            timeline.after(Self.pricingDelay) { [weak self] in
                guard let self else { return }
                self.chat?.appendCustom(self.pricingSections, stagger: 0.5, scrollDuration: 1.2)
            }
            return
        }
        chat.play([.tutorText(line)]) { [weak self] in
            self?.timeline.after(min(1, Double(line.count) * 0.008)) { [weak self] in
                self?.playNote(lines.dropFirst())
            }
        }
    }

    @objc private func skipAhead() {
        timeline.fastForward()
    }

    // MARK: Pieces

    private func makeTitle(for offering: PaywallOffering) -> UIView {
        let title = UILabel()
        let titleText = NSMutableAttributedString(
            string: offering.string("title", default: "Everything in "),
            attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor.label]
        )
        // "Pro" in the selected-token pill from sentence scrub.
        titleText.append(makePaywallTokenHighlight("Pro", font: .systemFont(ofSize: 26, weight: .heavy), traitCollection: traitCollection))
        title.attributedText = titleText
        title.accessibilityLabel = titleText.string.replacingOccurrences(of: "\u{FFFC}", with: "Pro")
        title.numberOfLines = 0

        // A little more air between Hana's last line and the paywall than between chat rows.
        let holder = UIStackView(arrangedSubviews: [title])
        holder.isLayoutMarginsRelativeArrangement = true
        holder.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)
        return holder
    }

    /// Bold hero glass compact's headline and subhead, as one section.
    private func makeCompactHeading(for offering: PaywallOffering) -> UIView {
        let font = UIFont.systemFont(ofSize: 34, weight: .heavy)
        let accent = offering.string("titleAccent", default: "conversation")
        let headlineText = NSMutableAttributedString(
            string: offering.string("title", default: "Immerse yourself in "),
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        headlineText.append(makePaywallTokenHighlight(accent, font: font, traitCollection: traitCollection))
        let headline = UILabel()
        headline.attributedText = headlineText
        headline.accessibilityLabel = headlineText.string.replacingOccurrences(of: "\u{FFFC}", with: accent)
        headline.numberOfLines = 0

        let subhead = UILabel()
        subhead.text = offering.string("subtitle", default: "Real conversations, real voices: Japanese the way it's actually spoken.")
        subhead.font = .systemFont(ofSize: 17, weight: .semibold)
        subhead.textColor = .label
        subhead.numberOfLines = 0

        // Extra air above for Hana's last line, and below for the cards.
        let heading = UIStackView(arrangedSubviews: [headline, subhead])
        heading.axis = .vertical
        heading.spacing = 14
        heading.isLayoutMarginsRelativeArrangement = true
        heading.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 10, trailing: 0)
        return heading
    }

    /// Title-only rows in a single glass card, so the plans stay close to the note.
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
