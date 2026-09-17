//
//  DialogueScoreReceiptView.swift
//  shizen
//
//  Native iOS score summary for the dialogue completion sheet.
//

import UIKit

final class DialogueScoreSummaryCardView: UIView {

    private static let horizontalInset: CGFloat = 18
    private static let verticalInset: CGFloat = 18
    private static let rowSpacing: CGFloat = 12

    private let tally: DialogueCompletionTally
    private let contentStack = UIStackView()
    private let pointsLabel = UILabel()

    init(tally: DialogueCompletionTally) {
        self.tally = tally
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerCurve = .continuous
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
        isAccessibilityElement = false

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = Self.rowSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        contentStack.addArrangedSubview(makeScoreHeader())

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        contentStack.addArrangedSubview(divider)
        contentStack.setCustomSpacing(14, after: divider)

        for line in tally.lines {
            contentStack.addArrangedSubview(
                makeRow(label: line.label, points: line.points, kind: line.kind)
            )
        }

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset),
        ])

        accessibilityElements = contentStack.arrangedSubviews.filter { $0 !== divider }
    }

    private func makeScoreHeader() -> UIView {
        let copyStack = UIStackView()
        copyStack.axis = .vertical
        copyStack.alignment = .leading
        copyStack.spacing = 2

        let caption = UILabel()
        caption.text = "SCORE"
        caption.font = .systemFont(ofSize: 11, weight: .bold)
        caption.textColor = .secondaryLabel

        pointsLabel.text = "\(tally.total)"
        let scoreFont = UIFont.systemFont(ofSize: 34, weight: .bold)
        pointsLabel.font = scoreFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 34) } ?? scoreFont
        pointsLabel.textColor = .label
        pointsLabel.adjustsFontSizeToFitWidth = true
        pointsLabel.minimumScaleFactor = 0.75
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let unitLabel = UILabel()
        unitLabel.text = "points"
        unitLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        unitLabel.textColor = .secondaryLabel
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)

        let scoreLine = UIStackView(arrangedSubviews: [pointsLabel, unitLabel])
        scoreLine.axis = .horizontal
        scoreLine.alignment = .lastBaseline
        scoreLine.spacing = 6

        copyStack.addArrangedSubview(caption)
        copyStack.addArrangedSubview(scoreLine)

        let badge = UIImageView(
            image: UIImage(
                systemName: "sparkles",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
            )
        )
        badge.tintColor = ExperimentPalette.meaningBadgeText
        badge.backgroundColor = ExperimentPalette.highlightFill
        badge.contentMode = .center
        badge.layer.cornerCurve = .continuous
        badge.layer.cornerRadius = 19
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 38),
            badge.heightAnchor.constraint(equalToConstant: 38),
        ])

        let header = UIStackView(arrangedSubviews: [copyStack, badge])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        header.isAccessibilityElement = true
        header.accessibilityLabel = "Score, \(tally.total) points"
        return header
    }

    private func makeRow(
        label: String,
        points: Int,
        kind: DialogueCompletionTally.Line.Kind
    ) -> UIView {
        let iconContainer = UIView()
        iconContainer.backgroundColor = iconBackground(for: kind)
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.layer.cornerRadius = 14
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(
            image: UIImage(
                systemName: iconName(for: kind),
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            )
        )
        icon.tintColor = pointsColor(for: kind)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 28),
            iconContainer.heightAnchor.constraint(equalToConstant: 28),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])

        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pointsLabel = UILabel()
        pointsLabel.text = Self.signedPoints(points)
        pointsLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        pointsLabel.textColor = pointsColor(for: kind)
        pointsLabel.textAlignment = .right
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [iconContainer, titleLabel, pointsLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(label), \(Self.signedPoints(points)) points"
        return row
    }

    private static func signedPoints(_ points: Int) -> String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(abs(points))" }
        return "+0"
    }

    private func pointsColor(for kind: DialogueCompletionTally.Line.Kind) -> UIColor {
        switch kind {
        case .deduction:
            return ExperimentPalette.errorBorder
        case .bonus:
            return ExperimentPalette.meaningBadgeText
        case .missed:
            return .tertiaryLabel
        case .credit:
            return .systemGreen
        }
    }

    private func iconBackground(for kind: DialogueCompletionTally.Line.Kind) -> UIColor {
        switch kind {
        case .deduction:
            return ExperimentPalette.errorFill
        case .bonus:
            return ExperimentPalette.highlightFill
        case .missed:
            return UIColor.tertiarySystemFill
        case .credit:
            return ExperimentPalette.successFill
        }
    }

    private func iconName(for kind: DialogueCompletionTally.Line.Kind) -> String {
        switch kind {
        case .deduction: return "text.bubble.fill"
        case .bonus: return "ear.fill"
        case .missed: return "xmark"
        case .credit: return "checkmark"
        }
    }
}
