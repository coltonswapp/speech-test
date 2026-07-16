//
//  CompactDefinitionCalloutView.swift
//  shizen
//
//  Compact single-gloss callout anchored to a token (above or below).
//

import UIKit

/// Small tappable bubble with an arrow for a single definition gloss.
final class CompactDefinitionCalloutView: UIControl {

    enum Placement {
        /// Bubble above the token; arrow at the bottom edge pointing down.
        case above
        /// Bubble below the token; arrow at the top edge pointing up.
        case below
    }

    var onDetailTapped: (() -> Void)?

    /// Raised above page content; one step lighter than secondary in dark mode.
    private static let bubbleFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemBackground
            : .secondarySystemBackground
    }

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = CompactDefinitionCalloutView.bubbleFill
        v.layer.cornerRadius = 8
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let textLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .callout)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.isUserInteractionEnabled = false
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let chevronView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        let iv = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: config))
        iv.tintColor = .quaternaryLabel
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let arrowView: UIView = {
        let v = UIView()
        v.backgroundColor = CompactDefinitionCalloutView.bubbleFill
        v.layer.cornerRadius = 3
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var arrowXConstraint: NSLayoutConstraint?
    private var arrowYConstraint: NSLayoutConstraint?
    private var containerTopConstraint: NSLayoutConstraint?
    private var containerBottomConstraint: NSLayoutConstraint?
    private var placement: Placement = .above
    private var cornerRadius: CGFloat = 8
    private let arrowSize: CGFloat = 10

    private static let horizontalPad: CGFloat = 12
    private static let verticalPad: CGFloat = 10
    private static let chevronWidth: CGFloat = 16
    private static let labelChevronGap: CGFloat = 4

    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = .clear
        textLabel.text = text
        accessibilityLabel = "Dictionary definition"
        accessibilityHint = "Shows the full dictionary entry"
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String) {
        textLabel.text = text
        invalidateIntrinsicContentSize()
    }

    func setPlacement(_ placement: Placement) {
        guard self.placement != placement else { return }
        self.placement = placement
        applyPlacementConstraints()
    }

    /// Applies the resolved bubble width so the single-line label truncates correctly.
    func prepareLayout(width: CGFloat) {
        let labelMaxWidth = max(
            0,
            width - Self.horizontalPad * 2 - Self.chevronWidth - Self.labelChevronGap
        )
        textLabel.preferredMaxLayoutWidth = labelMaxWidth
    }

    /// Align the arrow toward `pointX` in this view's coordinate space (e.g. token center).
    func updateArrowPosition(toward pointX: CGFloat) {
        guard let arrowXConstraint, bounds.width > 0 else { return }
        let arrowHalf = arrowSize / 2
        let margin = cornerRadius
        let minConstant = (margin + arrowHalf) - bounds.midX
        let maxConstant = (bounds.width - margin - arrowHalf) - bounds.midX
        let desired = pointX - bounds.midX
        arrowXConstraint.constant = max(minConstant, min(maxConstant, desired))
        layoutIfNeeded()
    }

    func showWithAnimation() {
        transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        alpha = 0
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    func dismissWithAnimation(completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.3,
            options: .curveEaseIn
        ) {
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    override var intrinsicContentSize: CGSize {
        fittingSize(maxWidth: .greatestFiniteMagnitude)
    }

    /// Size that fits the label, padding, chevron, and arrow tip (single line, truncated at `maxWidth`).
    func fittingSize(maxWidth: CGFloat) -> CGSize {
        let chrome = Self.horizontalPad * 2 + Self.labelChevronGap + Self.chevronWidth
        let labelMaxWidth = max(0, maxWidth - chrome)
        let unconstrained = textLabel.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        )
        let singleLineHeight = textLabel.font.lineHeight
        let labelWidth = min(ceil(unconstrained.width), labelMaxWidth)
        return CGSize(
            width: min(labelWidth + chrome, maxWidth),
            height: singleLineHeight + Self.verticalPad * 2 + arrowSize / 2
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
    }

    // MARK: - Setup

    private func setupUI() {
        clipsToBounds = false
        addSubview(arrowView)
        addSubview(containerView)
        containerView.addSubview(textLabel)
        containerView.addSubview(chevronView)

        addTarget(self, action: #selector(handleDetailTapped), for: .touchUpInside)

        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            arrowXConstraint!,
            arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
            arrowView.heightAnchor.constraint(equalToConstant: arrowSize),

            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            textLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Self.verticalPad),
            textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Self.horizontalPad),
            textLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Self.verticalPad),

            chevronView.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: Self.labelChevronGap),
            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Self.horizontalPad),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
            chevronView.heightAnchor.constraint(equalToConstant: Self.chevronWidth),
        ])

        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        containerView.clipsToBounds = true

        applyPlacementConstraints()
    }

    private func applyPlacementConstraints() {
        arrowYConstraint?.isActive = false
        containerTopConstraint?.isActive = false
        containerBottomConstraint?.isActive = false

        let half = arrowSize / 2
        switch placement {
        case .above:
            arrowYConstraint = arrowView.centerYAnchor.constraint(equalTo: containerView.bottomAnchor)
            containerTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
            containerBottomConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -half)
        case .below:
            arrowYConstraint = arrowView.centerYAnchor.constraint(equalTo: containerView.topAnchor)
            containerTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor, constant: half)
            containerBottomConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        }

        NSLayoutConstraint.activate([
            arrowYConstraint!,
            containerTopConstraint!,
            containerBottomConstraint!,
        ])
        setNeedsLayout()
    }

    @objc private func handleDetailTapped() {
        onDetailTapped?()
    }

    private func updateShadowPath() {
        let path = UIBezierPath()
        let containerRect = containerView.frame
        path.append(UIBezierPath(roundedRect: containerRect, cornerRadius: cornerRadius))

        let arrowRect = arrowView.frame
        switch placement {
        case .above:
            let tipPoint = CGPoint(x: arrowRect.midX, y: arrowRect.midY + arrowSize / 2)
            let l = CGPoint(x: arrowRect.midX - arrowSize / 2, y: containerRect.maxY)
            let r = CGPoint(x: arrowRect.midX + arrowSize / 2, y: containerRect.maxY)
            path.move(to: l)
            path.addLine(to: tipPoint)
            path.addLine(to: r)
            path.close()
        case .below:
            let tipPoint = CGPoint(x: arrowRect.midX, y: arrowRect.midY - arrowSize / 2)
            let l = CGPoint(x: arrowRect.midX - arrowSize / 2, y: containerRect.minY)
            let r = CGPoint(x: arrowRect.midX + arrowSize / 2, y: containerRect.minY)
            path.move(to: l)
            path.addLine(to: tipPoint)
            path.addLine(to: r)
            path.close()
        }

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = path.cgPath
    }
}
