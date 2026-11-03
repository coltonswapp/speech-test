//
//  PaywallHanaGlassViewController.swift
//  shizen
//
//  Variant: Hana pitch, brand edition. Slow-drifting brand-yellow blobs
//  behind Liquid Glass: Hana chats from a glass bubble that answers the selected
//  plan, a stack of glass feature rows, and short side-by-side glass plan tiles tinted
//  yellow when selected, pinned above the brand yellow CTA.
//

import UIKit

final class PaywallHanaGlassViewController: PaywallBaseViewController {
    private static let page = paywallDynamicColor(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.04, alpha: 1)
    )
    private static let ink = MascotTheme.darkInk.uiColor

    private let backdrop = BrandBlobBackdrop()
    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 88, height: 88))
    private let bubbleLabel = UILabel()
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
        let title = UILabel()
        let titleText = NSMutableAttributedString(
            string: offering.string("title", default: "Keep the conversation going with "),
            attributes: [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.label]
        )
        // "Pro" in the selected-token pill from sentence scrub.
        titleText.append(makePaywallTokenHighlight("Pro", font: .systemFont(ofSize: 30, weight: .heavy), traitCollection: traitCollection))
        title.attributedText = titleText
        title.accessibilityLabel = titleText.string.replacingOccurrences(of: "\u{FFFC}", with: "Pro")
        title.numberOfLines = 0

        rows = makePaywallPlanTiles(for: offering, compact: true, inlineUnit: true)
        bind(rows)
        let plans = makePaywallPlanTileRow(rows)
        // Room for the SAVE badge that straddles the tiles' top edge.
        plans.isLayoutMarginsRelativeArrangement = true
        plans.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)

        let content = UIStackView(arrangedSubviews: [makeHanaRow(), title, makeFeatureList()])
        content.axis = .vertical
        content.spacing = 22

        let cta = makeCTA(background: Colors.ctaYellow, foreground: Colors.ctaDarkYellow)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = .secondaryLabel
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0

        let footer = UIStackView(arrangedSubviews: [plans, cta, finePrint])
        footer.axis = .vertical
        footer.spacing = 8
        footer.setCustomSpacing(14, after: plans)

        installScrollLayout(content: content, footer: footer, horizontalInset: 20, topInset: 60)
        installTopBar(tint: .label)
    }

    override func selectedPackageDidChange(animated: Bool) {
        rows.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = PaywallCopy.ctaTitle(for: selectedPackage)
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)

        let line: String
        switch selectedPackage {
        case let package? where package.hasTrial:
            line = "Try everything free for \(package.trialDays!) days. I'll remind you before it ends!"
        case let package? where package.period == .annual:
            line = "Yearly's my favorite. That's a whole year of talking together."
        case .some:
            line = "Monthly works too. We can take it one month at a time."
        case nil:
            line = "Ready to keep going?"
        }
        guard line != bubbleLabel.text else { return }
        if animated {
            UIView.transition(with: bubbleLabel, duration: 0.25, options: .transitionCrossDissolve) {
                self.bubbleLabel.text = line
            }
            mascot.play(selectedPackage?.period == .annual ? .excited : .pleased)
        } else {
            bubbleLabel.text = line
        }
    }

    // MARK: Pieces

    private func makeGlass(radius: CGFloat, tint: UIColor? = nil) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = tint
        let glass = UIVisualEffectView(effect: effect)
        glass.cornerConfiguration = .corners(radius: .fixed(radius))
        glass.translatesAutoresizingMaskIntoConstraints = false
        return glass
    }

    /// Hana on the leading side talking from a glass bubble, like the onboarding capsules.
    private func makeHanaRow() -> UIView {
        mascot.translatesAutoresizingMaskIntoConstraints = false
        // Basic pink like onboarding and Profile, regardless of the user's saved theme.
        mascot.setTheme(.pink, animated: false)
        mascot.set(MascotPreset.happy.expression, animated: false)

        bubbleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        bubbleLabel.textColor = .label
        bubbleLabel.numberOfLines = 0
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false

        let bubble = makeGlass(radius: 22)
        bubble.contentView.addSubview(bubbleLabel)

        let row = UIView()
        row.addSubview(mascot)
        row.addSubview(bubble)
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: 88),
            mascot.heightAnchor.constraint(equalToConstant: 88),
            mascot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -6),
            mascot.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            mascot.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            bubble.leadingAnchor.constraint(equalTo: mascot.trailingAnchor, constant: 6),
            bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: row.topAnchor),
            // Bubble's bottom sits a little above Hana's base so it reads as coming from her.
            bubble.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -18),
            bubble.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            bubbleLabel.topAnchor.constraint(equalTo: bubble.contentView.topAnchor, constant: 14),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubble.contentView.bottomAnchor, constant: -14),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubble.contentView.leadingAnchor, constant: 16),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubble.contentView.trailingAnchor, constant: -16),
        ])
        // Hug the taller of Hana and the bubble.
        let hug = row.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeLevel
        hug.isActive = true
        return row
    }

    private func makeFeatureList() -> UIView {
        let list = UIStackView(arrangedSubviews: PaywallCopy.features.map { makeFeatureTile($0, fill: Colors.ctaYellow) })
        list.axis = .vertical
        list.spacing = 10
        return list
    }

    /// Full-width glass row: icon on the leading side, title and detail beside it.
    private func makeFeatureTile(_ feature: PaywallCopy.Feature, fill: UIColor) -> UIView {
        let iconSize: CGFloat = 36
        let icon = UIImageView(image: UIImage(systemName: feature.symbol))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.tintColor = Self.ink
        icon.contentMode = .center
        icon.backgroundColor = fill
        icon.layer.cornerRadius = iconSize / 2
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
        ])

        let title = UILabel()
        title.text = feature.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = feature.detail
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2

        let stack = UIStackView(arrangedSubviews: [icon, text])
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let glass = makeGlass(radius: 20)
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -12),
        ])
        return glass
    }
}

/// Big soft brand-yellow blobs that drift slowly, giving the glass something to bend.
final class BrandBlobBackdrop: UIView {
    private struct Blob {
        let layer: CAGradientLayer
        /// Center and diameter as fractions of the view's width / height.
        let center: CGPoint
        let drift: CGPoint
        let diameter: CGFloat
    }

    private var blobs: [Blob] = []
    private var isDrifting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let specs: [(UIColor, CGPoint, CGPoint, CGFloat)] = [
            (Colors.ctaYellow, CGPoint(x: 0.15, y: 0.08), CGPoint(x: 0.12, y: 0.05), 1.1),
            // A cool counterpoint to the yellow.
            (UIColor.systemBlue, CGPoint(x: 0.95, y: 0.3), CGPoint(x: -0.1, y: 0.06), 0.95),
            (Colors.ctaYellow, CGPoint(x: 0.1, y: 0.62), CGPoint(x: 0.14, y: -0.05), 1.0),
            (Colors.ctaYellow, CGPoint(x: 0.9, y: 0.9), CGPoint(x: -0.12, y: -0.04), 0.9),
        ]
        for (color, center, drift, diameter) in specs {
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.colors = [color.withAlphaComponent(0.7).cgColor, color.withAlphaComponent(0).cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(gradient)
            blobs.append(Blob(layer: gradient, center: center, drift: drift, diameter: diameter))
        }
        updateBlobOpacity()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BrandBlobBackdrop, _: UITraitCollection) in
            view.updateBlobOpacity()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for blob in blobs {
            let size = bounds.width * blob.diameter
            blob.layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            blob.layer.position = CGPoint(x: bounds.width * blob.center.x, y: bounds.height * blob.center.y)
        }
        CATransaction.commit()
        if isDrifting { addDriftAnimations() }
    }

    func startDrifting() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        isDrifting = true
        addDriftAnimations()
    }

    private func addDriftAnimations() {
        for (index, blob) in blobs.enumerated() {
            let drift = CABasicAnimation(keyPath: "position")
            drift.toValue = CGPoint(
                x: bounds.width * (blob.center.x + blob.drift.x),
                y: bounds.height * (blob.center.y + blob.drift.y)
            )
            drift.duration = 7 + Double(index) * 1.5
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            blob.layer.add(drift, forKey: "drift")
        }
    }

    private func updateBlobOpacity() {
        let opacity: Float = traitCollection.userInterfaceStyle == .dark ? 0.25 : 0.45
        blobs.forEach { $0.layer.opacity = opacity }
    }
}
