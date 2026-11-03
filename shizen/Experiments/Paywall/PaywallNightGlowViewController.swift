//
//  PaywallNightGlowViewController.swift
//  shizen
//
//  Variant: black page with a brand-yellow glow behind Hana, plain-symbol feature list, a
//  "Not sure yet? Enable free trial" switch, and per-week pricing (Beside feel).
//  The switch and plan selection stay in sync: trial on ↔ the plan that has one.
//

import UIKit

final class PaywallNightGlowViewController: PaywallBaseViewController {
    private static let card = UIColor(white: 1, alpha: 0.08)

    private let glow = CAGradientLayer()
    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 96, height: 96))
    private let trialSwitch = UISwitch()
    private var trialRow: UIView?
    private var rows: [PaywallPlanRow] = []
    private let finePrint = UILabel()

    override func viewDidLoad() {
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        glow.type = .radial
        glow.colors = [
            Colors.ctaYellow.withAlphaComponent(0.9).cgColor,
            UIColor(red: 0.96, green: 0.49, blue: 0.08, alpha: 0.35).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ]
        glow.locations = [0, 0.4, 1]
        // Centered behind Hana; the y radius reaches the layer's bottom edge so it never clips.
        glow.startPoint = CGPoint(x: 0.5, y: 0.45)
        glow.endPoint = CGPoint(x: 1.2, y: 1)
        view.layer.addSublayer(glow)
        super.viewDidLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        glow.frame = CGRect(x: 0, y: -view.bounds.height * 0.1, width: view.bounds.width, height: view.bounds.height * 0.6)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.75
        pulse.toValue = 1
        pulse.duration = 3
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "pulse")
        mascot.play(.excited)
    }

    override func render(_ offering: PaywallOffering) {
        mascot.translatesAutoresizingMaskIntoConstraints = false
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
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0

        let features = UIStackView(arrangedSubviews: PaywallCopy.features.map {
            makePaywallFeatureRow($0, style: .plain, titleColor: .white, showsDetail: false)
        })
        features.axis = .vertical
        features.spacing = 14
        features.isLayoutMarginsRelativeArrangement = true
        features.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)

        var arranged: [UIView] = [mascotHolder, title, features]
        if offering.packages.contains(where: \.hasTrial) {
            let row = makeTrialRow()
            trialRow = row
            arranged.append(row)
        }

        let palette = PaywallPlanRow.Palette(
            fill: Self.card,
            selectedFill: Self.card,
            border: UIColor(white: 1, alpha: 0.12),
            selectedBorder: Colors.ctaYellow,
            title: .white,
            detail: UIColor(white: 1, alpha: 0.6),
            indicator: .clear,
            badgeFill: Colors.ctaYellow,
            badgeText: .black
        )
        let monthly = offering.monthly
        rows = offering.packages.map { package in
            let savings = monthly.flatMap { package == $0 ? nil : package.savingsPercent(comparedTo: $0) }
            return PaywallPlanRow(
                package: package,
                title: package.period.title,
                subtitle: "\(package.localizedPrice)/\(package.period.unit)",
                trailing: "\(package.pricePerWeek)/week",
                badge: savings.map { "\($0)% DISCOUNT" },
                indicator: .none,
                palette: palette,
                cornerRadius: 16
            )
        }
        bind(rows)
        let plans = UIStackView(arrangedSubviews: rows)
        plans.axis = .vertical
        plans.spacing = 14
        arranged.append(plans)

        let content = UIStackView(arrangedSubviews: arranged)
        content.axis = .vertical
        content.spacing = 22
        content.setCustomSpacing(12, after: mascotHolder)
        content.setCustomSpacing(30, after: features)

        let cta = makeCTA(background: Colors.ctaYellow, foreground: .black)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = UIColor(white: 1, alpha: 0.5)
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0
        let links = makeLegalLinks(color: UIColor(white: 1, alpha: 0.5), includesRestore: true)
        let linksRow = UIStackView(arrangedSubviews: [links])
        linksRow.alignment = .center
        linksRow.axis = .vertical

        let footer = UIStackView(arrangedSubviews: [cta, finePrint, linksRow])
        footer.axis = .vertical
        footer.spacing = 10

        installScrollLayout(content: content, footer: footer, topInset: 64)
        installTopBar(tint: .white, showsRestore: false)
    }

    override func selectedPackageDidChange(animated: Bool) {
        rows.forEach { $0.isSelected = $0.package == selectedPackage }
        trialSwitch.setOn(selectedPackage?.hasTrial == true, animated: animated)
        ctaButton?.title = selectedPackage?.hasTrial == true ? "Try free & subscribe" : "Continue"
        finePrint.text = PaywallCopy.finePrint(for: selectedPackage)
        if animated { mascot.play(selectedPackage?.hasTrial == true ? .excited : .curious) }
    }

    private func makeTrialRow() -> UIView {
        let title = UILabel()
        title.text = "Not sure yet?"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        let detail = UILabel()
        detail.text = "Enable free trial"
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = UIColor(white: 1, alpha: 0.6)
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2

        trialSwitch.onTintColor = Colors.ctaYellow
        trialSwitch.addAction(UIAction { [weak self] _ in self?.trialSwitchChanged() }, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [text, trialSwitch])
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        row.backgroundColor = Self.card
        row.layer.cornerRadius = 16
        row.layer.cornerCurve = .continuous
        return row
    }

    private func trialSwitchChanged() {
        guard let offering else { return }
        let target = trialSwitch.isOn
            ? offering.packages.first(where: \.hasTrial)
            : offering.packages.first { !$0.hasTrial }
        if let target { select(target) } else { selectedPackageDidChange(animated: true) }
    }
}
