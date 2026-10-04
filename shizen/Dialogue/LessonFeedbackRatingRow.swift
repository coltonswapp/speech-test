//
//  LessonFeedbackRatingRow.swift
//  shizen
//
//  One rating dimension as five stars. A tap fills through that star; tapping
//  the same star again clears the row.
//

import UIKit

final class LessonFeedbackRatingRow: UIView {

    static let starSize: CGFloat = 36
    private static let starSpacing: CGFloat = 6
    private static let filledColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)
    private static let emptyColor = UIColor.tertiaryLabel

    let dimension: LessonFeedbackDimension
    private(set) var value: Int?
    var onChange: ((LessonFeedbackDimension, Int?) -> Void)?

    private let titleLabel = UILabel()
    private let starsStack = UIStackView()
    private var starViews: [UIImageView] = []
    private var buttons: [UIButton] = []
    private let selection = UISelectionFeedbackGenerator()

    init(dimension: LessonFeedbackDimension) {
        self.dimension = dimension
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        value = nil
        applySelection()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = dimension.title
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        starsStack.axis = .horizontal
        starsStack.alignment = .center
        starsStack.spacing = Self.starSpacing
        starsStack.setContentHuggingPriority(.required, for: .horizontal)

        let symbol = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        for rating in 1...5 {
            let imageView = UIImageView(image: UIImage(systemName: "star", withConfiguration: symbol))
            imageView.tintColor = Self.emptyColor
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let button = UIButton(type: .custom)
            button.accessibilityLabel = "\(rating)"
            button.addAction(UIAction { [weak self] _ in
                self?.tapped(rating)
            }, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(imageView)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.starSize),
                button.heightAnchor.constraint(equalToConstant: Self.starSize),
                imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            starsStack.addArrangedSubview(button)
            starViews.append(imageView)
            buttons.append(button)
        }

        let stack = UIStackView(arrangedSubviews: [titleLabel, starsStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = dimension.title
        accessibilityHint = dimension.prompt
        applySelection()
    }

    private func tapped(_ rating: Int) {
        set(value == rating ? nil : rating)
    }

    private func set(_ newValue: Int?) {
        guard newValue != value else { return }
        value = newValue
        selection.selectionChanged()
        applySelection()
        onChange?(dimension, value)
    }

    private func applySelection() {
        let symbol = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let filled = value ?? 0
        for (index, star) in starViews.enumerated() {
            let isOn = index < filled
            star.image = UIImage(systemName: isOn ? "star.fill" : "star", withConfiguration: symbol)
            star.tintColor = isOn ? Self.filledColor : Self.emptyColor
        }
        accessibilityValue = value.map { "\($0) of 5" } ?? "Not rated"
    }

    override func accessibilityIncrement() {
        set(min((value ?? 0) + 1, 5))
    }

    override func accessibilityDecrement() {
        guard let value else { return }
        set(value > 1 ? value - 1 : nil)
    }
}

/// "How was this lesson?" with one optional row per dimension.
final class LessonFeedbackPageView: UIView {

    var onSkip: (() -> Void)?

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let skipButton = UIButton(type: .system)
    private let rows = LessonFeedbackDimension.allCases.map(LessonFeedbackRatingRow.init(dimension:))

    var ratings: [LessonFeedbackDimension: Int] {
        var result: [LessonFeedbackDimension: Int] = [:]
        for row in rows {
            if let value = row.value {
                result[row.dimension] = value
            }
        }
        return result
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        rows.forEach { $0.clear() }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        headerLabel.text = "How was this lesson?"
        headerLabel.font = .systemFont(ofSize: 22, weight: .bold)
        headerLabel.textColor = .label
        headerLabel.numberOfLines = 0
        headerLabel.accessibilityTraits = .header

        subtitleLabel.text = "Rate any that stood out. All optional."
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        var skipConfig = UIButton.Configuration.plain()
        skipConfig.title = "Skip"
        skipConfig.baseForegroundColor = .secondaryLabel
        skipConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        skipButton.configuration = skipConfig
        skipButton.addAction(UIAction { [weak self] _ in
            self?.onSkip?()
        }, for: .touchUpInside)

        let rowsStack = UIStackView(arrangedSubviews: rows)
        rowsStack.axis = .vertical
        rowsStack.spacing = 4

        let stack = UIStackView(arrangedSubviews: [headerLabel, subtitleLabel, rowsStack, skipButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.setCustomSpacing(8, after: rowsStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
