import UIKit
@preconcurrency import Toast

// MARK: - API

enum Sentiment {
    case positive
    case negative
}

extension UIViewController {
    func showToast(
        delay: CGFloat = 0,
        text: String,
        subtitle: String? = nil,
        sentiment: Sentiment = .positive,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        ToastManager.shared.showToast(
            delay: delay,
            text: text,
            subtitle: subtitle,
            sentiment: sentiment,
            actionTitle: actionTitle,
            onAction: onAction
        )
    }

    /// Symbol plus one line, presented from the top edge.
    func showBanner(symbol: String, text: String, delay: CGFloat = 0) {
        ToastManager.shared.showBanner(symbol: symbol, text: text, delay: delay)
    }
}

// MARK: - Toast view

final class GlassToastView: UIView, ToastView {

    private static let cornerRadius: CGFloat = 16
    private static let horizontalInset: CGFloat = 16
    private static let contentPadding: CGFloat = 14
    private static let actionCornerRadius: CGFloat = 10

    /// Light: dark glass. Dark: translucent gray glass.
    private static let lightTint = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
    private static let darkTint = UIColor(red: 137 / 255, green: 137 / 255, blue: 137 / 255, alpha: 0.3)
    private static let lightActionFill = UIColor.white.withAlphaComponent(0.22)
    private static let darkActionFill = UIColor.white.withAlphaComponent(0.28)

    private let glassView: UIVisualEffectView
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let headerStack = UIStackView()
    private let contentStack = UIStackView()
    private var actionButton: UIButton?

    private weak var toast: Toast?
    private let onAction: (() -> Void)?
    private var didHandleAction = false

    init(
        title: String,
        subtitle: String? = nil,
        sentiment: Sentiment = .positive,
        symbolName: String? = nil,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            glassView = UIVisualEffectView(effect: glassEffect)
        } else {
            glassView = UIVisualEffectView(effect: nil)
        }

        self.onAction = onAction
        super.init(frame: .zero)

        setupChrome()
        setupContent(
            title: title,
            subtitle: subtitle,
            sentiment: sentiment,
            symbolName: symbolName,
            actionTitle: actionTitle
        )
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let fitting = contentStack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(
            width: fitting.width + Self.contentPadding * 2,
            height: fitting.height + Self.contentPadding * 2
        )
    }

    func createView(for toast: Toast) {
        self.toast = toast
        guard let superview else { return }

        translatesAutoresizingMaskIntoConstraints = false
        applyAppearance()

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(greaterThanOrEqualTo: superview.leadingAnchor, constant: Self.horizontalInset),
            trailingAnchor.constraint(lessThanOrEqualTo: superview.trailingAnchor, constant: -Self.horizontalInset),
            centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            widthAnchor.constraint(lessThanOrEqualTo: superview.widthAnchor, constant: -Self.horizontalInset * 2)
        ])

        switch toast.config.direction {
        case .bottom:
            bottomAnchor.constraint(equalTo: superview.layoutMarginsGuide.bottomAnchor).isActive = true
        case .top:
            topAnchor.constraint(equalTo: superview.layoutMarginsGuide.topAnchor).isActive = true
        case .center:
            centerYAnchor.constraint(equalTo: superview.layoutMarginsGuide.centerYAnchor).isActive = true
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyAppearance()
    }

    private func setupChrome() {
        backgroundColor = .clear
        layer.zPosition = 999

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.layer.cornerRadius = Self.cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true

        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupContent(
        title: String,
        subtitle: String?,
        sentiment: Sentiment,
        symbolName customSymbolName: String?,
        actionTitle: String?
    ) {
        let hasSubtitle = customSymbolName == nil && !(subtitle ?? "").isEmpty
        let hasAction = customSymbolName == nil && !(actionTitle ?? "").isEmpty
        let isSingleLine = !hasSubtitle && !hasAction

        let symbolName = customSymbolName ?? (sentiment == .positive ? "checkmark.circle" : "xmark.circle")
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24)
        ])

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = isSingleLine ? 1 : 2
        titleLabel.textAlignment = isSingleLine ? .center : .natural
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textStack.axis = .vertical
        textStack.alignment = isSingleLine ? .center : .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)

        if hasSubtitle, let subtitle {
            subtitleLabel.text = subtitle
            subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
            subtitleLabel.numberOfLines = 2
            textStack.addArrangedSubview(subtitleLabel)
        }

        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10
        headerStack.addArrangedSubview(iconView)
        headerStack.addArrangedSubview(textStack)

        contentStack.axis = .vertical
        contentStack.alignment = isSingleLine ? .center : .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(headerStack)

        if hasAction, let actionTitle {
            var configuration = UIButton.Configuration.filled()
            configuration.title = actionTitle
            configuration.cornerStyle = .fixed
            configuration.background.cornerRadius = Self.actionCornerRadius
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 14, weight: .semibold)
                return outgoing
            }

            let button = UIButton(configuration: configuration)
            button.addTarget(self, action: #selector(handleActionTap), for: .touchUpInside)
            actionButton = button
            contentStack.addArrangedSubview(button)
        }

        glassView.contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: Self.contentPadding),
            contentStack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: Self.contentPadding),
            contentStack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -Self.contentPadding),
            contentStack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -Self.contentPadding)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        invalidateIntrinsicContentSize()
    }

    private func applyAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let tint = isDark ? Self.darkTint : Self.lightTint

        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            glassEffect.tintColor = tint
            glassView.effect = glassEffect
            glassView.backgroundColor = nil
            layer.shadowOpacity = 0
        } else {
            glassView.effect = nil
            glassView.backgroundColor = tint
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 4)
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 10
            layer.masksToBounds = false
        }

        iconView.tintColor = .white
        titleLabel.textColor = .white
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)

        if var configuration = actionButton?.configuration {
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = isDark ? Self.darkActionFill : Self.lightActionFill
            actionButton?.configuration = configuration
        }
    }

    @objc private func handleActionTap() {
        guard !didHandleAction else { return }
        didHandleAction = true
        onAction?()
    }
}

// MARK: - Manager

enum ToastPresentationEdge {
    case top
    case bottom

    var toastDirection: Toast.Direction {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    /// +1 slides toward the bottom of the screen, -1 toward the top.
    var dismissSign: CGFloat {
        switch self {
        case .top: return -1
        case .bottom: return 1
        }
    }
}

final class ToastManager {
    static let shared = ToastManager()

    /// Change to `.top` to present from the top edge.
    var presentationEdge: ToastPresentationEdge = .bottom

    private static let overlayLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
    private static let stackScale: CGFloat = 0.92
    private static let stackOffsetY: CGFloat = -14
    private static let dismissScale: CGFloat = 0.92

    private let tuning = ToastAnimationTuning()
    private var toastWindow: PassthroughWindow?
    private var entries: [ToastEntry] = []
    private var swipeHandler: ToastSwipeHandler?

    private init() {}

    /// Symbol and one line of text, always from the top.
    func showBanner(symbol: String, text: String, delay: CGFloat = 0) {
        showToast(
            delay: delay,
            text: text,
            symbolName: symbol,
            edge: .top,
            visibleDuration: 2.4
        )
    }

    func showToast(
        delay: CGFloat = 0,
        text: String,
        subtitle: String? = nil,
        sentiment: Sentiment = .positive,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        symbolName: String? = nil,
        edge requestedEdge: ToastPresentationEdge? = nil,
        visibleDuration explicitDuration: TimeInterval? = nil
    ) {
        if toastWindow == nil {
            setupToastWindow()
        }

        let present: () -> Void = { [weak self] in
            guard let self else { return }

            self.toastWindow?.isHidden = false

            let edge = requestedEdge ?? self.presentationEdge
            let hasAction = symbolName == nil && actionTitle != nil && onAction != nil
            let visibleDuration = explicitDuration ?? (hasAction ? 4.5 : 3.0)

            var dismissBy: [Toast.Dismissable] = [.longPress]
            if !hasAction {
                dismissBy.append(.tap)
            }

            let enterY = self.tuning.translateY * edge.dismissSign
            let exitTransform = Self.dismissTransform(
                travel: self.tuning.dismissTranslateY,
                sign: edge.dismissSign
            )

            let config = ToastConfiguration(
                direction: edge.toastDirection,
                dismissBy: dismissBy,
                animationTime: self.tuning.dismissDuration,
                enteringAnimation: .custom(transformation: .identity),
                exitingAnimation: .custom(transformation: exitTransform),
                attachTo: self.toastWindow?.rootViewController?.view,
                allowToastOverlap: true
            )

            let entryID = UUID()
            let toastView = GlassToastView(
                title: text,
                subtitle: subtitle,
                sentiment: sentiment,
                symbolName: symbolName,
                actionTitle: actionTitle,
                onAction: { [weak self] in
                    guard let self else { return }
                    self.dismissEntry(id: entryID, animated: true)
                    DispatchQueue.main.async {
                        onAction?()
                    }
                }
            )

            let toast = Toast.custom(view: toastView, config: config)
            let entry = ToastEntry(
                id: entryID,
                toast: toast,
                view: toastView,
                edge: edge,
                dismissDeadline: Date().addingTimeInterval(visibleDuration)
            )

            let coordinator = ToastDismissalCoordinator { [weak self] in
                self?.removeEntry(id: entryID, viewAlreadyRemoved: true)
            }
            entry.coordinator = coordinator
            toast.addDelegate(delegate: coordinator)

            self.entries.append(entry)

            let startTransform = CGAffineTransform(translationX: 0, y: enterY)
                .scaledBy(x: self.tuning.initialScale, y: self.tuning.initialScale)

            toast.show()

            toastView.layer.removeAllAnimations()
            toastView.alpha = 0
            toastView.transform = startTransform

            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)

            UIView.animate(
                withDuration: self.tuning.duration,
                delay: 0,
                usingSpringWithDamping: self.tuning.damping,
                initialSpringVelocity: self.tuning.velocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                toastView.alpha = 1
                toastView.transform = .identity
            } completion: { [weak self] _ in
                self?.relayoutStack(animated: true)
            }

            self.relayoutStack(animated: true)
            self.attachSwipeHandlerToPrimary()
            self.scheduleDismiss(for: entry, after: visibleDuration)
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: present)
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }

    private func setupToastWindow() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = Self.overlayLevel
        window.backgroundColor = .clear
        window.isHidden = true

        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC

        toastWindow = window
    }

    private func scheduleDismiss(for entry: ToastEntry, after delay: TimeInterval) {
        entry.dismissTimer?.invalidate()
        let id = entry.id
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { [weak self] _ in
            self?.dismissEntry(id: id, animated: true)
        }
        entry.dismissTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func dismissEntry(id: UUID, animated: Bool) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        guard !entry.isDismissing else { return }
        entry.isDismissing = true
        entry.dismissTimer?.invalidate()
        entry.dismissTimer = nil

        let view = entry.view
        let isPrimary = entries.last?.id == id

        if isPrimary {
            swipeHandler = nil
            view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
        }
        view.isUserInteractionEnabled = false

        let finish = { [weak self] in
            self?.removeEntry(id: id, viewAlreadyRemoved: false)
        }

        guard animated else {
            finish()
            return
        }

        view.layoutIfNeeded()
        let travel = max(tuning.dismissTranslateY, view.bounds.height + 28)
        let exitTransform = Self.dismissTransform(travel: travel, sign: entry.edge.dismissSign)

        UIView.animate(
            withDuration: tuning.dismissDuration,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            view.transform = exitTransform
            view.alpha = 1
        } completion: { _ in
            finish()
        }
    }

    private func removeEntry(id: UUID, viewAlreadyRemoved: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.dismissTimer?.invalidate()
        entry.isDismissing = true

        if !viewAlreadyRemoved {
            entry.view.layer.removeAllAnimations()
            entry.view.removeFromSuperview()
            entry.toast.close(animated: false)
        }

        relayoutStack(animated: true)
        attachSwipeHandlerToPrimary()

        if entries.isEmpty {
            swipeHandler = nil
            toastWindow?.isHidden = true
        }
    }

    private func relayoutStack(animated: Bool) {
        let changes = {
            let activeEntries = self.entries.filter { !$0.isDismissing }
            for (index, entry) in activeEntries.enumerated() {
                let depth = activeEntries.count - 1 - index
                entry.view.layer.zPosition = CGFloat(1000 - depth)

                if depth == 0 {
                    entry.view.transform = .identity
                    entry.view.isUserInteractionEnabled = true
                } else {
                    let scale = pow(Self.stackScale, CGFloat(depth))
                    let stackEdge = activeEntries.last?.edge ?? self.presentationEdge
                    let stackStep = stackEdge == .top ? -Self.stackOffsetY : Self.stackOffsetY
                    let offset = stackStep * CGFloat(depth)
                    entry.view.transform = CGAffineTransform(translationX: 0, y: offset)
                        .scaledBy(x: scale, y: scale)
                    entry.view.isUserInteractionEnabled = false
                }
                entry.view.alpha = 1
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.5,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func attachSwipeHandlerToPrimary() {
        swipeHandler = nil
        guard let primary = entries.last else { return }

        for entry in entries {
            entry.view.gestureRecognizers?.forEach { entry.view.removeGestureRecognizer($0) }
        }

        let primaryID = primary.id
        let handler = ToastSwipeHandler(
            toast: primary.toast,
            dismissSign: primary.edge.dismissSign,
            dismissTravel: tuning.dismissTranslateY,
            dismissScale: Self.dismissScale,
            dismissDuration: tuning.dismissDuration,
            onPanBegan: { [weak primary] in
                primary?.dismissTimer?.invalidate()
                primary?.dismissTimer = nil
            },
            onSnapBack: { [weak self, weak primary] in
                guard let self, let primary, self.entries.contains(where: { $0.id == primary.id }) else { return }
                let remaining = max(0.75, primary.dismissDeadline.timeIntervalSinceNow)
                self.scheduleDismiss(for: primary, after: remaining)
            },
            onInteractiveDismissFinished: { [weak self] in
                self?.removeEntry(id: primaryID, viewAlreadyRemoved: true)
            }
        )
        swipeHandler = handler
        primary.view.addGestureRecognizer(handler.panRecognizer)
        primary.view.isUserInteractionEnabled = true
    }

    private static func dismissTransform(travel: CGFloat, sign: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: 0, y: travel * sign)
            .scaledBy(x: dismissScale, y: dismissScale)
    }
}

private struct ToastAnimationTuning {
    var duration: TimeInterval = 0.26
    var damping: CGFloat = 0.61
    var velocity: CGFloat = 0.91
    var initialScale: CGFloat = 0.94
    var translateY: CGFloat = 56
    var dismissDuration: TimeInterval = 0.15
    var dismissTranslateY: CGFloat = 80
}

private final class ToastEntry {
    let id: UUID
    let toast: Toast
    let view: GlassToastView
    let edge: ToastPresentationEdge
    let dismissDeadline: Date
    var dismissTimer: Timer?
    var coordinator: ToastDismissalCoordinator?
    var isDismissing = false

    init(
        id: UUID,
        toast: Toast,
        view: GlassToastView,
        edge: ToastPresentationEdge,
        dismissDeadline: Date
    ) {
        self.id = id
        self.toast = toast
        self.view = view
        self.edge = edge
        self.dismissDeadline = dismissDeadline
    }
}

private final class ToastDismissalCoordinator: ToastDelegate {
    private let onDidClose: () -> Void
    private var didHandle = false

    init(onDidClose: @escaping () -> Void) {
        self.onDidClose = onDidClose
    }

    func willShowToast(_ toast: Toast) {}
    func didShowToast(_ toast: Toast) {}
    func willCloseToast(_ toast: Toast) {}

    func didCloseToast(_ toast: Toast) {
        guard !didHandle else { return }
        didHandle = true
        onDidClose()
    }
}

private final class ToastSwipeHandler: NSObject, UIGestureRecognizerDelegate {
    let panRecognizer = UIPanGestureRecognizer()

    private weak var toast: Toast?
    private let dismissSign: CGFloat
    private let dismissTravel: CGFloat
    private let dismissScale: CGFloat
    private let dismissDuration: TimeInterval
    private let onPanBegan: () -> Void
    private let onSnapBack: () -> Void
    private let onInteractiveDismissFinished: () -> Void

    private var startTranslationY: CGFloat = 0
    private var startScale: CGFloat = 1
    private var didFinish = false

    init(
        toast: Toast,
        dismissSign: CGFloat,
        dismissTravel: CGFloat,
        dismissScale: CGFloat,
        dismissDuration: TimeInterval,
        onPanBegan: @escaping () -> Void,
        onSnapBack: @escaping () -> Void,
        onInteractiveDismissFinished: @escaping () -> Void
    ) {
        self.toast = toast
        self.dismissSign = dismissSign
        self.dismissTravel = dismissTravel
        self.dismissScale = dismissScale
        self.dismissDuration = dismissDuration
        self.onPanBegan = onPanBegan
        self.onSnapBack = onSnapBack
        self.onInteractiveDismissFinished = onInteractiveDismissFinished
        super.init()

        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        panRecognizer.delegate = self
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = toast?.view, !didFinish else { return }

        switch gesture.state {
        case .began:
            startTranslationY = view.transform.ty
            startScale = hypot(view.transform.a, view.transform.c)
            if startScale == 0 { startScale = 1 }
            onPanBegan()

        case .changed:
            let delta = gesture.translation(in: view.superview).y
            var translationY = startTranslationY + delta
            if dismissSign > 0 {
                translationY = translationY < 0 ? translationY * 0.2 : translationY
            } else {
                translationY = translationY > 0 ? translationY * 0.2 : translationY
            }

            let progress = min(1, abs(translationY) / max(dismissTravel, 1))
            let scale = startScale + (dismissScale - startScale) * progress
            view.transform = CGAffineTransform(translationX: 0, y: translationY)
                .scaledBy(x: scale, y: scale)
            view.alpha = 1

        case .ended, .cancelled:
            let translationY = view.transform.ty
            let velocityY = gesture.velocity(in: view.superview).y
            let distance = abs(translationY)
            let projectedTravel = distance + abs(velocityY) * 0.12
            let movingInDismissDirection = velocityY * dismissSign > 0
            let shouldDismiss =
                distance > 20
                || (movingInDismissDirection && abs(velocityY) > 450)
                || projectedTravel > dismissTravel * 0.55

            if shouldDismiss, gesture.state == .ended {
                finishInteractiveDismiss(from: translationY, velocityY: velocityY, view: view)
            } else {
                UIView.animate(
                    withDuration: 0.35,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.4,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    view.transform = .identity
                    view.alpha = 1
                } completion: { [weak self] _ in
                    self?.onSnapBack()
                }
            }

        default:
            break
        }
    }

    private func finishInteractiveDismiss(from currentY: CGFloat, velocityY: CGFloat, view: UIView) {
        didFinish = true

        let targetY = dismissSign * max(dismissTravel, abs(currentY) + 36)
        let distance = abs(targetY - currentY)
        let velocity = max(abs(velocityY), 1)
        let duration = min(dismissDuration, max(0.12, distance / velocity))

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            view.transform = CGAffineTransform(translationX: 0, y: targetY)
                .scaledBy(x: self.dismissScale, y: self.dismissScale)
            view.alpha = 1
        } completion: { [weak self] _ in
            guard let self else { return }
            self.toast?.close(animated: false)
            self.onInteractiveDismissFinished()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if touch.view is UIControl { return false }
        return true
    }
}
