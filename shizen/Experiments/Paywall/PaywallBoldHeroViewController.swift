//
//  PaywallBoldHeroViewController.swift
//  shizen
//
//  Variant: huge headline on a saturated grid backdrop, monospaced feature callouts,
//  and a light bottom sheet with radio plans and a black CTA (Universe feel).
//

import UIKit

final class PaywallBoldHeroViewController: PaywallBaseViewController {
    private static let hero = UIColor(red: 0.95, green: 0.2, blue: 0.29, alpha: 1)
    private static let sheetFill = UIColor(red: 1, green: 0.95, blue: 0.95, alpha: 1)

    private var rows: [PaywallPlanRow] = []
    private let finePrint = UILabel()

    override func viewDidLoad() {
        overrideUserInterfaceStyle = .light
        view.backgroundColor = Self.hero
        super.viewDidLoad()
    }

    override func render(_ offering: PaywallOffering) {
        let grid = PaywallGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let headline = UILabel()
        headline.text = offering.string("title", default: "Speak\nJapanese\nfor real")
        headline.font = .systemFont(ofSize: 56, weight: .heavy)
        headline.textColor = .white
        headline.numberOfLines = 0
        headline.adjustsFontSizeToFitWidth = true
        headline.minimumScaleFactor = 0.6

        let subhead = UILabel()
        subhead.text = offering.string("subtitle", default: "Learn from real conversations and practice them out loud with Hana.")
        subhead.font = .systemFont(ofSize: 20, weight: .semibold)
        subhead.textColor = .white
        subhead.numberOfLines = 0

        let callouts = UIStackView(arrangedSubviews: ["EVERY LESSON, NEW WEEKLY", "UNLIMITED VOICE PRACTICE", "KANJI + GRAMMAR ON TAP"].map { text in
            let label = UILabel()
            label.text = "▸ " + text
            label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            label.textColor = UIColor.white.withAlphaComponent(0.9)
            return label
        })
        callouts.axis = .vertical
        callouts.spacing = 10

        let content = UIStackView(arrangedSubviews: [headline, subhead, callouts])
        content.axis = .vertical
        content.spacing = 20
        content.setCustomSpacing(28, after: subhead)

        // Bottom sheet
        let palette = PaywallPlanRow.Palette(
            fill: .clear,
            selectedFill: UIColor.white.withAlphaComponent(0.85),
            border: .clear,
            selectedBorder: .black,
            title: .black,
            detail: UIColor.black.withAlphaComponent(0.55),
            indicator: UIColor.black.withAlphaComponent(0.4),
            badgeFill: Self.hero,
            badgeText: .white
        )
        let monthly = offering.monthly
        rows = offering.packages.map { package in
            let savings = monthly.flatMap { package == $0 ? nil : package.savingsPercent(comparedTo: $0) }
            return PaywallPlanRow(
                package: package,
                title: "\(package.period.title): \(package.localizedPrice)",
                subtitle: package.period == .monthly ? "Month by month" : "Only \(package.pricePerMonth)/month",
                trailing: savings.map { "Save \($0)%" },
                indicator: .radio,
                palette: palette,
                cornerRadius: 14
            )
        }
        bind(rows)

        let cta = makeCTA(background: .black, foreground: .white)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = UIColor.black.withAlphaComponent(0.55)
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0
        let links = UIStackView(arrangedSubviews: [
            makeLegalLinks(color: UIColor.black.withAlphaComponent(0.5), includesRestore: true, underlined: true),
        ])
        links.axis = .vertical
        links.alignment = .center

        let sheetStack = UIStackView(arrangedSubviews: rows + [cta, finePrint, links])
        sheetStack.axis = .vertical
        sheetStack.spacing = 8
        sheetStack.alignment = .fill
        if let last = rows.last { sheetStack.setCustomSpacing(18, after: last) }
        sheetStack.setCustomSpacing(10, after: cta)
        sheetStack.translatesAutoresizingMaskIntoConstraints = false

        let sheet = UIView()
        sheet.backgroundColor = Self.sheetFill
        sheet.layer.cornerRadius = 32
        sheet.layer.cornerCurve = .continuous
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(sheetStack)

        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        view.addSubview(sheet)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: sheet.topAnchor, constant: -20),

            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetStack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 24),
            sheetStack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 16),
            sheetStack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -16),
            sheetStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
        // Let the headline give way before the sheet does on small phones.
        headline.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        installTopBar(tint: .white, showsRestore: false)
    }

    override func selectedPackageDidChange(animated: Bool) {
        rows.forEach { $0.isSelected = $0.package == selectedPackage }
        ctaButton?.title = selectedPackage?.hasTrial == true ? PaywallCopy.ctaTitle(for: selectedPackage) : "Upgrade"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
    }
}

/// Faint square grid behind the hero.
final class PaywallGridView: UIView {
    private let spacing: CGFloat = 28
    /// Dynamic colors resolve against the view's traits when drawn.
    var lineColor = UIColor.white.withAlphaComponent(0.1) {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        lineColor.setStroke()
        path.lineWidth = 1 / max(traitCollection.displayScale, 1)
        path.stroke()
    }
}
