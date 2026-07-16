//
//  DefinitionTipView.swift
//  shizen
//
//  Tip-styled popover: arrow + rounded card, header (word + dismiss), scrollable definition body.
//

import UIKit

/// On-screen definition presented with the same visual language as `TipView` (arrow, card, shadow, dismiss).
final class DefinitionTipView: UIView {

    private let surface: String
    private let entries: [JMDictEntry]

    private var dismissHandler: (() -> Void)?
    private weak var sourceView: UIView?
    private var arrowXConstraint: NSLayoutConstraint?

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .headline)
        l.textColor = .label
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let dismissButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.tintColor = .tertiaryLabel
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.alwaysBounceVertical = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 3
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let arrowView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 3
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var cornerRadius: CGFloat = 12
    private let maxScrollHeight: CGFloat

    init(surface: String, entries: [JMDictEntry], maxScrollHeight: CGFloat? = nil, dismissHandler: (() -> Void)? = nil) {
        self.surface = surface
        self.entries = entries
        self.dismissHandler = dismissHandler
        self.maxScrollHeight = maxScrollHeight ?? min(3000, UIScreen.main.bounds.height * 0.95)
        super.init(frame: .zero)
        backgroundColor = .clear
        setup()
        buildDefinitionContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSourceView(_ view: UIView) { sourceView = view }

    func setDismissHandler(_ handler: @escaping () -> Void) { dismissHandler = handler }

    func updateArrowPosition() {
        guard let sourceView, let superview else { return }
        let sourceFrame = sourceView.superview?.convert(sourceView.frame, to: superview) ?? .zero
        let sourceCenterX = sourceFrame.midX
        let offset = sourceCenterX - frame.midX
        let maxOffset = bounds.width * 0.4
        arrowXConstraint?.constant = max(-maxOffset, min(maxOffset, offset))
    }

    func showWithAnimation() {
        transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    func dismissWithAnimation(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: .curveEaseIn) {
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
    }

    // MARK: - Setup (arrow = top of bubble, popover below source — matches `TipView` + `.bottom`)

    private func setup() {
        titleLabel.text = surface
        addSubview(arrowView)
        addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(dismissButton)
        containerView.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let widthPad: CGFloat = 12
        let dismissSize: CGFloat = 24
        let arrowSize: CGFloat = 12
        let half = arrowSize / 2
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            arrowXConstraint!,
            arrowView.centerYAnchor.constraint(equalTo: containerView.topAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
            arrowView.heightAnchor.constraint(equalToConstant: arrowSize),

            containerView.topAnchor.constraint(equalTo: topAnchor, constant: max(4, half - 2)),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            dismissButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: widthPad),
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: dismissSize),
            dismissButton.heightAnchor.constraint(equalToConstant: dismissSize),

            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: widthPad),
            titleLabel.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: widthPad),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: widthPad),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -widthPad),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -widthPad),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: maxScrollHeight),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

        dismissButton.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
    }

    private func buildDefinitionContent() {
        let subFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let caption = UIFont.preferredFont(forTextStyle: .caption1)

        if entries.isEmpty {
            let empty = UILabel()
            empty.text = "No dictionary entry found for this word."
            empty.font = bodyFont
            empty.textColor = .secondaryLabel
            empty.numberOfLines = 0
            contentStack.addArrangedSubview(empty)
            return
        }

        if let first = entries.first {
            let reading = UILabel()
            reading.text = JMDictStore.shared.readingForSurface(surface, matching: first)
            reading.font = subFont
            reading.textColor = .secondaryLabel
            reading.numberOfLines = 0
            contentStack.addArrangedSubview(reading)
        }

        var groups: [Int: [JMDictEntry]] = [:]
        var order: [Int] = []
        for e in entries {
            if groups[e.sequence] == nil {
                order.append(e.sequence)
            }
            groups[e.sequence, default: []].append(e)
        }

        for (groupIdx, sequence) in order.enumerated() {
            if groupIdx > 0 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                contentStack.addArrangedSubview(sep)
            }

            guard let groupRows = groups[sequence] else { continue }
            let sorted = groupRows.sorted { ($0.score ?? 0) > ($1.score ?? 0) }

            if order.count > 1, let one = sorted.first {
                let expr = UILabel()
                let y = one.displayReading
                if y == one.expression {
                    expr.text = one.expression
                } else {
                    expr.text = "\(one.expression) · \(y)"
                }
                expr.font = UIFont.preferredFont(forTextStyle: .headline)
                expr.numberOfLines = 0
                contentStack.addArrangedSubview(expr)
            }

            for (senseIdx, row) in sorted.enumerated() {
                let line = NSMutableAttributedString()
                line.append(NSAttributedString(
                    string: "\(senseIdx + 1). ",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                ))
                let gloss = row.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
                line.append(NSAttributedString(string: gloss, attributes: [.font: bodyFont, .foregroundColor: UIColor.label]))
                if let tags = row.tags, !tags.isEmpty {
                    line.append(NSAttributedString(
                        string: "  ·  \(tags)",
                        attributes: [.font: caption, .foregroundColor: UIColor.tertiaryLabel]
                    ))
                }
                let label = UILabel()
                label.attributedText = line
                label.numberOfLines = 0
                contentStack.addArrangedSubview(label)
            }
        }
    }

    private func updateShadowPath() {
        let path = UIBezierPath()
        let containerRect = containerView.frame
        let arrowRect = arrowView.frame
        let arrowSize: CGFloat = 12

        path.append(UIBezierPath(roundedRect: containerRect, cornerRadius: cornerRadius))

        // Arrow at top of card, pointing up (popover below source) — same as `TipArrowEdge.bottom` in `TipView`.
        let tipP = CGPoint(x: arrowRect.midX, y: arrowRect.midY - arrowSize / 2)
        let l = CGPoint(x: arrowRect.midX - arrowSize / 2, y: containerRect.minY)
        let r = CGPoint(x: arrowRect.midX + arrowSize / 2, y: containerRect.minY)
        path.move(to: l); path.addLine(to: tipP); path.addLine(to: r); path.close()

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = .zero
        layer.shadowPath = path.cgPath
    }

    @objc private func handleDismiss() { dismissHandler?() }
}
