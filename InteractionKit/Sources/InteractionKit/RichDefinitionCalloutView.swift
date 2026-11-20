//
//  RichDefinitionCalloutView.swift
//  InteractionKit
//
//  Larger token callout: headword + reading, dictionary form and part of speech,
//  and the first few senses. Same bubble, arrow, and shadow as `CompactDefinitionCalloutView`.
//

import UIKit

/// What a `RichDefinitionCalloutView` shows. Built by the app from its dictionary.
public struct DefinitionCalloutContent: Equatable {
    /// The tapped surface, as it appears in the sentence.
    public var headword: String
    /// Kana reading of `headword`. Nil (or equal to `headword`) hides it.
    public var reading: String?
    /// Dictionary form when it differs from `headword` (歩いて → 歩く).
    public var dictionaryForm: String?
    /// Short part-of-speech line, e.g. "godan verb · intransitive".
    public var partOfSpeech: String?
    /// Senses in dictionary order. The view shows at most `maxSenses`.
    public var senses: [String]
    /// Shown when `senses` is empty, e.g. "Not in the dictionary yet".
    public var emptyMessage: String?
    /// Small line under the senses, e.g. "Depends on context · tap for its meaning here".
    public var note: String?

    public init(
        headword: String,
        reading: String? = nil,
        dictionaryForm: String? = nil,
        partOfSpeech: String? = nil,
        senses: [String] = [],
        emptyMessage: String? = nil,
        note: String? = nil
    ) {
        self.headword = headword
        self.reading = reading
        self.dictionaryForm = dictionaryForm
        self.partOfSpeech = partOfSpeech
        self.senses = senses
        self.emptyMessage = emptyMessage
        self.note = note
    }
}

public final class RichDefinitionCalloutView: UIControl {

    public static let maxSenses = 3

    public var onDetailTapped: (() -> Void)?

    /// Press and hold on the bubble. Nil removes the gesture, so a plain tap is unaffected.
    public var onLongPress: (() -> Void)? {
        didSet { updateLongPressGesture() }
    }
    private var longPressGesture: UILongPressGestureRecognizer?

    private static let bubbleFill = DefinitionCalloutOutline.bubbleFill
    private let rimLayer = DefinitionCalloutOutline.makeRimLayer()

    private static let horizontalPad: CGFloat = 14
    private static let verticalPad: CGFloat = 12
    private static let chevronWidth: CGFloat = 16
    private static let chevronGap: CGFloat = 8
    private static let minWidth: CGFloat = 200
    private let arrowSize: CGFloat = 10
    private let cornerRadius: CGFloat = 12

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = RichDefinitionCalloutView.bubbleFill
        v.layer.cornerRadius = 12
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let arrowView: UIView = {
        let v = UIView()
        v.backgroundColor = RichDefinitionCalloutView.bubbleFill
        v.layer.cornerRadius = 3
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let stack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = 4
        s.isUserInteractionEnabled = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let chevronView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let iv = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: config))
        iv.tintColor = .tertiaryLabel
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var labels: [UILabel] = []
    private var placement: CompactDefinitionCalloutView.Placement = .above
    private var arrowXConstraint: NSLayoutConstraint?
    private var arrowYConstraint: NSLayoutConstraint?
    private var containerTopConstraint: NSLayoutConstraint?
    private var containerBottomConstraint: NSLayoutConstraint?

    public init(content: DefinitionCalloutContent) {
        super.init(frame: .zero)
        backgroundColor = .clear
        accessibilityHint = "Shows the full dictionary entry"
        setupUI()
        setContent(content)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Content

    public func setContent(_ content: DefinitionCalloutContent) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        labels = []

        // Headword + reading
        let title = NSMutableAttributedString(
            string: content.headword,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title3).withWeight(.semibold),
                .foregroundColor: UIColor.label,
            ]
        )
        if let reading = content.reading?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reading.isEmpty, reading != content.headword {
            title.append(NSAttributedString(
                string: "  \(reading)",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            ))
        }
        let titleLabel = makeLabel(lines: 2)
        titleLabel.attributedText = title
        stack.addArrangedSubview(titleLabel)

        // Dictionary form · part of speech
        var metaParts: [String] = []
        if let form = content.dictionaryForm, !form.isEmpty, form != content.headword {
            metaParts.append("→ \(form)")
        }
        if let pos = content.partOfSpeech, !pos.isEmpty {
            metaParts.append(pos)
        }
        if !metaParts.isEmpty {
            let meta = makeLabel(lines: 1)
            meta.text = metaParts.joined(separator: "  ·  ")
            meta.font = .preferredFont(forTextStyle: .footnote)
            meta.textColor = .secondaryLabel
            stack.addArrangedSubview(meta)
        }
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last ?? titleLabel)

        // Senses
        let senses = Array(content.senses.prefix(Self.maxSenses))
        if senses.isEmpty {
            let empty = makeLabel(lines: 2)
            empty.text = content.emptyMessage ?? "No dictionary entry"
            empty.font = .preferredFont(forTextStyle: .subheadline)
            empty.textColor = .secondaryLabel
            stack.addArrangedSubview(empty)
        } else {
            let bodyFont = UIFont.preferredFont(forTextStyle: .subheadline)
            for (index, sense) in senses.enumerated() {
                let line = NSMutableAttributedString()
                if senses.count > 1 {
                    line.append(NSAttributedString(
                        string: "\(index + 1). ",
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.tertiaryLabel]
                    ))
                }
                line.append(NSAttributedString(
                    string: sense,
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
                ))
                let label = makeLabel(lines: 2)
                label.attributedText = line
                stack.addArrangedSubview(label)
            }
        }

        if let note = content.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            stack.setCustomSpacing(8, after: stack.arrangedSubviews.last ?? titleLabel)
            let noteLabel = makeLabel(lines: 2)
            noteLabel.text = note
            noteLabel.font = .preferredFont(forTextStyle: .footnote)
            noteLabel.textColor = .secondaryLabel
            stack.addArrangedSubview(noteLabel)
        }

        var spoken: [String] = [content.headword]
        if let reading = content.reading, reading != content.headword { spoken.append(reading) }
        spoken += metaParts
        spoken += senses.isEmpty ? [content.emptyMessage ?? "No dictionary entry"] : senses
        if let note = content.note, !note.isEmpty { spoken.append(note) }
        accessibilityLabel = spoken.joined(separator: ", ")
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func makeLabel(lines: Int) -> UILabel {
        let l = UILabel()
        l.numberOfLines = lines
        l.lineBreakMode = .byTruncatingTail
        l.adjustsFontForContentSizeCategory = true
        l.isUserInteractionEnabled = false
        labels.append(l)
        return l
    }

    // MARK: - Long press

    private func updateLongPressGesture() {
        if onLongPress == nil {
            if let longPressGesture { removeGestureRecognizer(longPressGesture) }
            longPressGesture = nil
            return
        }
        guard longPressGesture == nil else { return }
        // Recognizing cancels the touch, so the tap (`touchUpInside`) does not also fire.
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.minimumPressDuration = 0.6
        addGestureRecognizer(gesture)
        longPressGesture = gesture
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?()
    }

    // MARK: - Sizing

    private var horizontalChrome: CGFloat {
        Self.horizontalPad * 2 + Self.chevronGap + Self.chevronWidth
    }

    public func prepareLayout(width: CGFloat) {
        let labelWidth = max(0, width - horizontalChrome)
        labels.forEach { $0.preferredMaxLayoutWidth = labelWidth }
    }

    /// Widest label's natural width (clamped to `maxWidth`), then the stack height at that width.
    public func fittingSize(maxWidth: CGFloat) -> CGSize {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let natural = labels.map { ceil($0.sizeThatFits(unbounded).width) }.max() ?? 0
        let width = min(maxWidth, max(min(Self.minWidth, maxWidth), natural + horizontalChrome))
        prepareLayout(width: width)
        let stackHeight = stack.systemLayoutSizeFitting(
            CGSize(width: width - horizontalChrome, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return CGSize(
            width: width,
            height: ceil(stackHeight) + Self.verticalPad * 2 + arrowSize / 2
        )
    }

    // MARK: - Placement & arrow

    public func setPlacement(_ placement: CompactDefinitionCalloutView.Placement) {
        guard self.placement != placement else { return }
        self.placement = placement
        applyPlacementConstraints()
    }

    public func updateArrowPosition(toward pointX: CGFloat) {
        guard let arrowXConstraint, bounds.width > 0 else { return }
        let arrowHalf = arrowSize / 2
        let margin = cornerRadius
        let minConstant = (margin + arrowHalf) - bounds.midX
        let maxConstant = (bounds.width - margin - arrowHalf) - bounds.midX
        arrowXConstraint.constant = max(minConstant, min(maxConstant, pointX - bounds.midX))
        layoutIfNeeded()
    }

    // MARK: - Animation

    /// Scale the bubble grows from / shrinks back to, around the arrow tip.
    private static let collapsedScale: CGFloat = 0.5

    /// Grows out of the word: scales up from the arrow tip with a slight overshoot.
    public func showWithAnimation() {
        layer.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else {
            transform = .identity
            alpha = 0
            UIView.animate(withDuration: 0.2) { self.alpha = 1 }
            return
        }
        anchorScaleAtArrowTip()
        transform = CGAffineTransform(scaleX: Self.collapsedScale, y: Self.collapsedScale)
        alpha = 0
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.62,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        }
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.alpha = 1
        }
    }

    /// Shrinks back into the word, then removes itself.
    public func dismissWithAnimation(completion: (() -> Void)? = nil) {
        isUserInteractionEnabled = false
        guard !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: 0.15, delay: 0, options: .beginFromCurrentState) {
                self.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
                completion?()
            }
            return
        }
        anchorScaleAtArrowTip()
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.transform = CGAffineTransform(scaleX: Self.collapsedScale, y: Self.collapsedScale)
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    /// Small dip-and-spring when the open bubble moves to another word.
    func pulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        anchorScaleAtArrowTip()
        transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.6,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        }
    }

    /// Moves the layer's anchor to the arrow tip without moving the bubble, so scaling
    /// grows from / collapses into the tapped word.
    private func anchorScaleAtArrowTip() {
        layoutIfNeeded()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let tipX = arrowView.frame.midX / bounds.width
        let tipY: CGFloat = placement == .above ? 1 : 0
        let anchor = CGPoint(x: min(max(tipX, 0), 1), y: tipY)
        guard layer.anchorPoint != anchor else { return }
        let savedTransform = transform
        transform = .identity
        let savedFrame = frame
        layer.anchorPoint = anchor
        frame = savedFrame
        transform = savedTransform
    }

    /// Clears any running scale so the presenter can set `frame` safely.
    func settleForLayout() {
        layer.removeAllAnimations()
        transform = .identity
        alpha = 1
    }

    // MARK: - Setup

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
        updateRim()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        rimLayer.strokeColor = DefinitionCalloutOutline.rimColor(for: traitCollection).cgColor
    }

    /// Hairline rim around box + pointer: light in dark mode, faint dark in light.
    private func updateRim() {
        if rimLayer.superlayer !== layer {
            layer.addSublayer(rimLayer)
        }
        rimLayer.strokeColor = DefinitionCalloutOutline.rimColor(for: traitCollection).cgColor
        rimLayer.frame = bounds
        rimLayer.path = DefinitionCalloutOutline.path(
            container: containerView.frame,
            cornerRadius: cornerRadius,
            arrowMidX: arrowView.frame.midX,
            arrowSize: arrowSize,
            arrowPointsDown: placement == .above
        ).cgPath
    }

    private func setupUI() {
        clipsToBounds = false
        addSubview(arrowView)
        addSubview(containerView)
        containerView.addSubview(stack)
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

            stack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Self.verticalPad),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Self.horizontalPad),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Self.verticalPad),

            chevronView.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: Self.chevronGap),
            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Self.horizontalPad),
            chevronView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Self.verticalPad + 4),
            chevronView.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
            chevronView.heightAnchor.constraint(equalToConstant: Self.chevronWidth),
        ])
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
        NSLayoutConstraint.activate([arrowYConstraint!, containerTopConstraint!, containerBottomConstraint!])
        setNeedsLayout()
    }

    @objc private func handleDetailTapped() {
        onDetailTapped?()
    }

    private func updateShadowPath() {
        let path = UIBezierPath(roundedRect: containerView.frame, cornerRadius: cornerRadius)
        let arrowRect = arrowView.frame
        let containerRect = containerView.frame
        let edgeY = placement == .above ? containerRect.maxY : containerRect.minY
        let tipY = placement == .above ? arrowRect.midY + arrowSize / 2 : arrowRect.midY - arrowSize / 2
        path.move(to: CGPoint(x: arrowRect.midX - arrowSize / 2, y: edgeY))
        path.addLine(to: CGPoint(x: arrowRect.midX, y: tipY))
        path.addLine(to: CGPoint(x: arrowRect.midX + arrowSize / 2, y: edgeY))
        path.close()

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = path.cgPath
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
