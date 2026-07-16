//
//  EncouragementBadgeView.swift
//  shizen
//
//  Pill badge with fill, white stroke, and soft drop shadow (combo / tensai labels).
//

import UIKit

final class EncouragementBadgeView: UIView {

    private static let titleFontSize: CGFloat = 27
    private static let cornerRadius: CGFloat = 24
    private static let verticalPadding: CGFloat = 12
    private static let horizontalPadding: CGFloat = 26

    private let fillView = UIView()
    private let titleLabel = UILabel()

    init(text: String, fillColor: UIColor, textColor: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = text

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.22

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.backgroundColor = fillColor
        fillView.layer.cornerRadius = Self.cornerRadius
        fillView.layer.borderWidth = 3
        fillView.layer.borderColor = UIColor.white.cgColor
        fillView.clipsToBounds = true

        titleLabel.text = text
        titleLabel.font = .systemFont(ofSize: Self.titleFontSize, weight: .heavy)
        titleLabel.textColor = textColor
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fillView)
        fillView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: fillView.topAnchor, constant: Self.verticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: fillView.bottomAnchor, constant: -Self.verticalPadding),
            titleLabel.leadingAnchor.constraint(equalTo: fillView.leadingAnchor, constant: Self.horizontalPadding),
            titleLabel.trailingAnchor.constraint(equalTo: fillView.trailingAnchor, constant: -Self.horizontalPadding),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForCascadeEntry() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.92, y: 0.92)
    }

    /// One-shot shimmer over the badge fill after layout is final.
    func playEntryShimmer() {
        layoutIfNeeded()
        fillView.playShimmer()
    }
}
