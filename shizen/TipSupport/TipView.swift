import UIKit

// MARK: - TipView

/// A self-contained tooltip popover with a directional arrow, icon, title, optional message, and dismiss button.
/// Use `init(tip:inline:)` for a full-width strip without an arrow (e.g. inside a sheet).
///
/// Customization points:
///   - `accentColor`        – tint of the icon (default: .systemYellow)
///   - `backgroundColor`    – container fill (default: .secondarySystemBackground)
///   - `cornerRadius`       – container corner radius (default: 12)
final class TipView: UIView {

    // MARK: - Configuration

    var accentColor: UIColor = .systemYellow {
        didSet { iconImageView.tintColor = accentColor }
    }

    override var backgroundColor: UIColor? {
        get { containerView.backgroundColor }
        set {
            containerView.backgroundColor = newValue
            arrowView.backgroundColor = newValue
        }
    }

    var cornerRadius: CGFloat = 12 {
        didSet { containerView.layer.cornerRadius = cornerRadius }
    }

    // MARK: - Properties

    private let tip: TipModel
    private let isInline: Bool
    private let arrowEdge: TipArrowEdge
    private var dismissHandler: (() -> Void)?
    private weak var sourceView: UIView?
    private var arrowXConstraint: NSLayoutConstraint?
    private var arrowYConstraint: NSLayoutConstraint?

    var tipId: String { tip.id }

    // MARK: - Subviews

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemYellow
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
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

    private let arrowView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 3
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Init (popover / anchored)

    init(tip: TipModel, arrowEdge: TipArrowEdge = .bottom, dismissHandler: (() -> Void)? = nil) {
        self.tip = tip
        self.isInline = false
        self.arrowEdge = arrowEdge
        self.dismissHandler = dismissHandler
        super.init(frame: .zero)
        super.backgroundColor = .clear
        setupUI()
        configureTip()
    }

    /// Full-width card without arrow, for embedding under navigation or in a stack.
    init(tip: TipModel, inline: Bool, dismissHandler: (() -> Void)? = nil) {
        self.tip = tip
        self.isInline = inline
        self.arrowEdge = .bottom
        self.dismissHandler = dismissHandler
        super.init(frame: .zero)
        super.backgroundColor = .clear
        setupUI()
        configureTip()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public API

    func setSourceView(_ view: UIView) { sourceView = view }

    func setDismissHandler(_ handler: @escaping () -> Void) { dismissHandler = handler }

    /// Call after the view has been laid out to align the arrow with the source view.
    func updateArrowPosition() {
        if isInline { return }
        guard let sourceView, let superview else { return }

        let sourceFrame = sourceView.superview?.convert(sourceView.frame, to: superview) ?? .zero
        let sourceCenterX = sourceFrame.midX
        let sourceCenterY = sourceFrame.midY
        let tooltipFrame = frame

        switch arrowEdge {
        case .top, .bottom:
            guard let arrowXConstraint else { return }
            let offset = sourceCenterX - tooltipFrame.midX
            let maxOffset = bounds.width * 0.4
            arrowXConstraint.constant = max(-maxOffset, min(maxOffset, offset))

        case .leading, .trailing:
            guard let arrowYConstraint else { return }
            let offset = sourceCenterY - tooltipFrame.midY
            let maxOffset = bounds.height * 0.4
            arrowYConstraint.constant = max(-maxOffset, min(maxOffset, offset))
        }
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

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
    }

    // MARK: - Setup

    private func setupUI() {
        if isInline {
            arrowView.isHidden = true
        } else {
            addSubview(arrowView)
        }
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(dismissButton)

        setupContainerConstraints()
        if isInline {
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            setupArrow()
        }
        dismissButton.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
    }

    private func setupContainerConstraints() {
        let pad: CGFloat = 12
        let iconSize: CGFloat = 32
        let dismissSize: CGFloat = 24

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: pad),
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: pad),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            dismissButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: pad),
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: dismissSize),
            dismissButton.heightAnchor.constraint(equalToConstant: dismissSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: pad),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -pad)
        ])
    }

    private func setupArrow() {
        let size: CGFloat = 12
        let half = size / 2
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)

        switch arrowEdge {
        case .top:
            // Tooltip above source → arrow at bottom pointing down
            arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)
            NSLayoutConstraint.activate([
                arrowXConstraint!,
                arrowView.centerYAnchor.constraint(equalTo: containerView.bottomAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: size),
                arrowView.heightAnchor.constraint(equalToConstant: size),
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -half)
            ])

        case .bottom:
            // Tooltip below source → arrow at top pointing up
            arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)
            NSLayoutConstraint.activate([
                arrowXConstraint!,
                arrowView.centerYAnchor.constraint(equalTo: containerView.topAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: size),
                arrowView.heightAnchor.constraint(equalToConstant: size),
                containerView.topAnchor.constraint(equalTo: topAnchor, constant: half),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

        case .leading:
            NSLayoutConstraint.activate([
                arrowView.centerXAnchor.constraint(equalTo: containerView.leadingAnchor),
                arrowView.centerYAnchor.constraint(equalTo: centerYAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: size),
                arrowView.heightAnchor.constraint(equalToConstant: size),
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: half),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

        case .trailing:
            arrowYConstraint = arrowView.centerYAnchor.constraint(equalTo: centerYAnchor)
            NSLayoutConstraint.activate([
                arrowView.centerXAnchor.constraint(equalTo: containerView.trailingAnchor),
                arrowYConstraint!,
                arrowView.widthAnchor.constraint(equalToConstant: size),
                arrowView.heightAnchor.constraint(equalToConstant: size),
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -half),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func configureTip() {
        titleLabel.text = tip.title
        iconImageView.image = UIImage(systemName: tip.systemImageName)

        if isInline {
            titleLabel.numberOfLines = 1
            titleLabel.lineBreakMode = .byTruncatingTail
            messageLabel.numberOfLines = 2
            messageLabel.lineBreakMode = .byTruncatingTail
        }

        if let msg = tip.message, !msg.isEmpty {
            messageLabel.text = msg
            messageLabel.isHidden = false
        } else {
            messageLabel.isHidden = true
        }
    }

    private func updateShadowPath() {
        let path = UIBezierPath()
        let containerRect = containerView.frame

        path.append(UIBezierPath(roundedRect: containerRect, cornerRadius: cornerRadius))

        if isInline {
            applyShadowPath(path)
            return
        }

        let arrowRect = arrowView.frame
        let arrowSize: CGFloat = 12

        switch arrowEdge {
        case .top:
            let tipPoint = CGPoint(x: arrowRect.midX, y: arrowRect.midY + arrowSize / 2)
            let l = CGPoint(x: arrowRect.midX - arrowSize / 2, y: containerRect.maxY)
            let r = CGPoint(x: arrowRect.midX + arrowSize / 2, y: containerRect.maxY)
            path.move(to: l); path.addLine(to: tipPoint); path.addLine(to: r); path.close()

        case .bottom:
            let tipPoint = CGPoint(x: arrowRect.midX, y: arrowRect.midY - arrowSize / 2)
            let l = CGPoint(x: arrowRect.midX - arrowSize / 2, y: containerRect.minY)
            let r = CGPoint(x: arrowRect.midX + arrowSize / 2, y: containerRect.minY)
            path.move(to: l); path.addLine(to: tipPoint); path.addLine(to: r); path.close()

        case .leading:
            let tipPoint = CGPoint(x: arrowRect.midX - arrowSize / 2, y: arrowRect.midY)
            let t = CGPoint(x: containerRect.minX, y: arrowRect.midY - arrowSize / 2)
            let b = CGPoint(x: containerRect.minX, y: arrowRect.midY + arrowSize / 2)
            path.move(to: t); path.addLine(to: tipPoint); path.addLine(to: b); path.close()

        case .trailing:
            let tipPoint = CGPoint(x: arrowRect.midX + arrowSize / 2, y: arrowRect.midY)
            let t = CGPoint(x: containerRect.maxX, y: arrowRect.midY - arrowSize / 2)
            let b = CGPoint(x: containerRect.maxX, y: arrowRect.midY + arrowSize / 2)
            path.move(to: t); path.addLine(to: tipPoint); path.addLine(to: b); path.close()
        }

        applyShadowPath(path)
    }

    private func applyShadowPath(_ path: UIBezierPath) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = .zero
        layer.shadowPath = path.cgPath
    }

    // MARK: - Actions

    @objc private func handleDismiss() { dismissHandler?() }
}
