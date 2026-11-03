//
//  PaywallTimelineViewController.swift
//  shizen
//
//  Variant: spells out how the trial works — today, the reminder, the billing day —
//  so the reminder promise from the notification ask pays off here. Yearly / Monthly
//  segmented switch; the timeline rebuilds for plans without a trial.
//

import UIKit

final class PaywallTimelineViewController: PaywallBaseViewController {
    private static let accent = UIColor(red: 0.95, green: 0.2, blue: 0.29, alpha: 1)

    private let timeline = UIStackView()
    private let segmented = UISegmentedControl()
    private let priceLabel = UILabel()
    private let finePrint = UILabel()
    private let headline = UILabel()

    override func viewDidLoad() {
        view.backgroundColor = .systemBackground
        super.viewDidLoad()
    }

    override func render(_ offering: PaywallOffering) {
        headline.font = .systemFont(ofSize: 30, weight: .bold)
        headline.numberOfLines = 0
        headline.textAlignment = .center

        timeline.axis = .vertical
        timeline.spacing = 0

        for (index, package) in offering.packages.enumerated() {
            segmented.insertSegment(withTitle: package.period.title, at: index, animated: false)
        }
        segmented.selectedSegmentIndex = offering.packages.firstIndex { $0 == selectedPackage } ?? 0
        segmented.addAction(UIAction { [weak self] _ in
            guard let self, let offering = self.offering else { return }
            self.select(offering.packages[self.segmented.selectedSegmentIndex])
        }, for: .valueChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.heightAnchor.constraint(equalToConstant: 36).isActive = true

        priceLabel.font = .systemFont(ofSize: 15, weight: .medium)
        priceLabel.textAlignment = .center
        priceLabel.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [headline, timeline])
        content.axis = .vertical
        content.spacing = 32

        let cta = makeCTA(background: Self.accent, foreground: .white)
        finePrint.font = .systemFont(ofSize: 12)
        finePrint.textColor = .secondaryLabel
        finePrint.textAlignment = .center
        finePrint.numberOfLines = 0

        let footer = UIStackView(arrangedSubviews: [segmented, priceLabel, cta, finePrint, makeLegalLinks(color: .tertiaryLabel)])
        footer.axis = .vertical
        footer.alignment = .fill
        footer.spacing = 12
        footer.setCustomSpacing(16, after: priceLabel)
        footer.setCustomSpacing(6, after: finePrint)

        installScrollLayout(content: content, footer: footer, horizontalInset: 28, topInset: 72)
        installTopBar(tint: .label)
    }

    override func selectedPackageDidChange(animated: Bool) {
        guard let package = selectedPackage else { return }
        if let index = offering?.packages.firstIndex(of: package) { segmented.selectedSegmentIndex = index }
        ctaButton?.title = PaywallCopy.ctaTitle(for: package)
        finePrint.text = PaywallCopy.finePrint(for: package)
        headline.text = package.hasTrial ? "How your free trial works" : "Here's what you get"

        let price = NSMutableAttributedString(string: "\(package.localizedPrice)/\(package.period.unit)", attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        if package.period != .monthly {
            price.append(NSAttributedString(string: "  ·  \(package.pricePerMonth)/mo", attributes: [.foregroundColor: UIColor.secondaryLabel]))
        }
        priceLabel.attributedText = price

        let rebuild = { self.rebuildTimeline(for: package) }
        if animated {
            UIView.transition(with: timeline, duration: 0.25, options: .transitionCrossDissolve, animations: rebuild)
        } else {
            rebuild()
        }
    }

    private struct Step {
        let symbol: String
        let title: String
        let detail: String
        let tint: UIColor
    }

    private func rebuildTimeline(for package: PaywallPackage) {
        timeline.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let dates = DateFormatter()
        dates.setLocalizedDateFormatFromTemplate("MMMd")
        let calendar = Calendar.current
        let today = Date()

        var steps = [Step(
            symbol: "lock.open.fill",
            title: "Today",
            detail: "Every lesson, Hana's voice practice, and tap-any-word breakdowns unlock.",
            tint: Self.accent
        )]
        if let days = package.trialDays {
            let reminder = calendar.date(byAdding: .day, value: max(days - 2, 1), to: today) ?? today
            let billing = calendar.date(byAdding: .day, value: days, to: today) ?? today
            steps.append(Step(
                symbol: "bell.fill",
                title: "Day \(max(days - 2, 1)) · \(dates.string(from: reminder))",
                detail: "Hana sends you a reminder that your trial is ending.",
                tint: .systemOrange
            ))
            steps.append(Step(
                symbol: "star.fill",
                title: "Day \(days) · \(dates.string(from: billing))",
                detail: "You're charged \(package.localizedPrice). Cancel anytime before and you won't pay a thing.",
                tint: .systemYellow
            ))
        } else {
            let renewal = calendar.date(byAdding: package.period == .annual ? .year : .month, value: 1, to: today) ?? today
            steps.append(Step(
                symbol: "arrow.triangle.2.circlepath",
                title: "Renews \(dates.string(from: renewal))",
                detail: "\(package.localizedPrice) each \(package.period.unit). Cancel anytime in Settings.",
                tint: .systemGray
            ))
        }

        for (index, step) in steps.enumerated() {
            timeline.addArrangedSubview(makeStepRow(step, isLast: index == steps.count - 1))
        }
    }

    private func makeStepRow(_ step: Step, isLast: Bool) -> UIView {
        let iconSize: CGFloat = 40
        let icon = UIImageView(image: UIImage(systemName: step.symbol))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        icon.tintColor = .white
        icon.contentMode = .center
        icon.backgroundColor = step.tint
        icon.layer.cornerRadius = iconSize / 2
        icon.translatesAutoresizingMaskIntoConstraints = false

        let rail = UIView()
        rail.backgroundColor = step.tint.withAlphaComponent(0.35)
        rail.isHidden = isLast
        rail.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = step.title
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let detail = UILabel()
        detail.text = step.detail
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = UIView()
        row.addSubview(rail)
        row.addSubview(icon)
        row.addSubview(text)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: row.topAnchor),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),

            rail.topAnchor.constraint(equalTo: icon.bottomAnchor),
            rail.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            rail.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            rail.widthAnchor.constraint(equalToConstant: 4),

            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: isLast ? 0 : -28),
        ])
        return row
    }
}
