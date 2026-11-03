//
//  PaywallCompareViewController.swift
//  shizen
//
//  Variant: Free vs Pro comparison table above two side-by-side plan cards
//  (Perplexity feel). Quiet, light, teal accent.
//

import UIKit

final class PaywallCompareViewController: PaywallBaseViewController {
    private static let accent = UIColor(red: 0.13, green: 0.5, blue: 0.53, alpha: 1)
    private static let card = paywallDynamicColor(light: .white, dark: .secondarySystemBackground)

    private enum Cell {
        case check, dash, text(String)
    }

    private static let comparison: [(String, Cell, Cell)] = [
        ("Kana & starter lessons", .check, .check),
        ("Real-conversation lessons", .text("3"), .text("All")),
        ("Speak with Hana", .dash, .check),
        ("Tap-any-word breakdowns", .text("5/day"), .text("∞")),
        ("Kanji spotlight", .dash, .check),
        ("Smart review", .dash, .check),
    ]

    private var cards: [PlanCard] = []
    private let finePrint = UILabel()

    override func viewDidLoad() {
        view.backgroundColor = paywallDynamicColor(light: UIColor(red: 0.95, green: 0.96, blue: 0.95, alpha: 1), dark: .systemBackground)
        super.viewDidLoad()
    }

    override func render(_ offering: PaywallOffering) {
        let title = UILabel()
        title.text = offering.string("title", default: "Understand Japanese\nthe way it's spoken")
        title.font = .systemFont(ofSize: 26, weight: .regular)
        title.numberOfLines = 0
        title.textAlignment = .center

        let table = makeTable()

        let monthly = offering.monthly
        cards = offering.packages.map { package in
            PlanCard(
                package: package,
                badge: monthly.flatMap { package == $0 ? nil : package.savingsPercent(comparedTo: $0) }.map { "-\($0)%" },
                accent: Self.accent,
                fill: Self.card
            )
        }
        for card in cards {
            card.addAction(UIAction { [weak self, weak card] _ in
                guard let card else { return }
                self?.select(card.package)
            }, for: .touchUpInside)
        }
        let plans = UIStackView(arrangedSubviews: cards)
        plans.spacing = 12
        plans.distribution = .fillEqually

        let content = UIStackView(arrangedSubviews: [title, table, plans])
        content.axis = .vertical
        content.spacing = 24
        content.setCustomSpacing(28, after: table)

        let cta = makeCTA(background: Self.accent, foreground: .white)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = .secondaryLabel
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0
        let footer = UIStackView(arrangedSubviews: [cta, finePrint])
        footer.axis = .vertical
        footer.spacing = 10

        installScrollLayout(content: content, footer: footer, horizontalInset: 20, topInset: 72)
        installTopBar(tint: .label)
    }

    override func selectedPackageDidChange(animated: Bool) {
        cards.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? PaywallCopy.ctaTitle(for: selectedPackage) : "Get Pro"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
    }

    private func makeTable() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        stack.backgroundColor = Self.card
        stack.layer.cornerRadius = 24
        stack.layer.cornerCurve = .continuous

        stack.addArrangedSubview(makeTableRow(
            "Features",
            .text("Free"),
            .text("Pro"),
            font: .systemFont(ofSize: 14, weight: .medium),
            color: .secondaryLabel,
            proColor: Self.accent
        ))
        for (feature, free, pro) in Self.comparison {
            stack.addArrangedSubview(makeTableRow(feature, free, pro, font: .systemFont(ofSize: 15), color: .label, proColor: Self.accent))
        }
        return stack
    }

    private func makeTableRow(_ title: String, _ free: Cell, _ pro: Cell, font: UIFont, color: UIColor, proColor: UIColor) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = font
        label.textColor = color
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [label, makeCell(free, color: .tertiaryLabel), makeCell(pro, color: proColor)])
        row.spacing = 8
        row.alignment = .center
        return row
    }

    private func makeCell(_ cell: Cell, color: UIColor) -> UIView {
        let view: UIView
        switch cell {
        case .check, .dash:
            let image = UIImageView(image: UIImage(systemName: { () -> String in
                if case .check = cell { return "checkmark" }
                return "minus"
            }()))
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            image.tintColor = color
            image.contentMode = .center
            view = image
        case .text(let text):
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textColor = color
            label.textAlignment = .center
            view = label
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return view
    }
}

/// Vertical plan card: period, big price, per-month line; check badge when selected.
private final class PlanCard: UIControl {
    let package: PaywallPackage
    private let accent: UIColor
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    /// Border sits on a background view so it never draws over the check badge.
    private let surface = UIView()

    init(package: PaywallPackage, badge: String?, accent: UIColor, fill: UIColor) {
        self.package = package
        self.accent = accent
        super.init(frame: .zero)
        surface.backgroundColor = fill
        surface.layer.cornerRadius = 20
        surface.layer.cornerCurve = .continuous
        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(package.period.title), \(package.localizedPrice) per \(package.period.unit)"

        let period = UILabel()
        period.text = package.period.title
        period.font = .systemFont(ofSize: 14)
        period.textColor = .secondaryLabel
        let header = UIStackView(arrangedSubviews: [period])
        header.spacing = 6
        if let badge {
            header.addArrangedSubview(PaywallBadgeLabel(text: badge, fill: accent.withAlphaComponent(0.15), textColor: accent))
        }

        let price = UILabel()
        let priceText = NSMutableAttributedString(string: package.localizedPrice, attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .medium)])
        priceText.append(NSAttributedString(string: " /\(package.period.shortUnit)", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.secondaryLabel,
        ]))
        price.attributedText = priceText
        price.adjustsFontSizeToFitWidth = true
        price.minimumScaleFactor = 0.7

        let detail = UILabel()
        detail.text = package.period == .monthly
            ? "\(PaywallPriceFormatter.string(package.price * 12, currencyCode: package.currencyCode))/yr"
            : "\(package.pricePerMonth)/mo"
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .tertiaryLabel

        let stack = UIStackView(arrangedSubviews: [header, price, detail])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        check.tintColor = accent
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        check.backgroundColor = fill
        check.layer.cornerRadius = 11
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            check.centerYAnchor.constraint(equalTo: topAnchor, constant: 2),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 4),
        ])
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: PlanCard, _: UITraitCollection) in
            card.updateAppearance()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            accessibilityTraits = isSelected ? [.button, .selected] : .button
            UIView.animate(withDuration: 0.2) { self.updateAppearance() }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    private func updateAppearance() {
        surface.layer.borderWidth = isSelected ? 2 : 1
        surface.layer.borderColor = (isSelected ? accent : .separator).resolvedColor(with: traitCollection).cgColor
        check.alpha = isSelected ? 1 : 0
        check.transform = isSelected ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
    }
}
