//
//  LLMFeedbackRow.swift
//  shizen
//
//  Two glass thumbs on a card edge. They start as one blob and separate.
//  A recorded vote fades them out.
//

import CryptoKit
import UIKit

enum LLMFeedbackRating: String {
    case up
    case down
}

enum LLMFeedbackReason: String, CaseIterable {
    case wrongMeaning = "wrong_meaning"
    case notAboutSentence = "not_about_sentence"
    case confusing

    var title: String {
        switch self {
        case .wrongMeaning: return "Wrong meaning"
        case .notAboutSentence: return "Not about this sentence"
        case .confusing: return "Confusing"
        }
    }
}

/// Raw generate fields needed to redeem a feedback token. Display cleanup is not included.
struct LLMFeedbackReceipt {
    let requestId: String
    let feedbackToken: String
    let feature: String
    let model: String
    let inputObject: Any
    let resultObject: Any
}

enum LLMFeedbackDevice {
    private static let defaultsKey = "llmFeedbackDeviceId"

    /// App-generated id for the soft per-device signal. Not an advertising identifier.
    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey),
           existing.count >= 8,
           existing.count <= 64 {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: defaultsKey)
        return created
    }
}

/// Asks on about every fourth new gloss. A vote is remembered so that gloss is not asked again.
enum LLMFeedbackPrompt {
    private static let countKey = "llmFeedbackOfferCount"
    private static let votedRequestKey = "llmFeedbackVotedRequestIds"
    private static let votedContentKey = "llmFeedbackVotedContentKeys"
    private static let askEvery = 4
    private static var sessionDecisions: [String: Bool] = [:]

    static func shouldOffer(_ receipt: LLMFeedbackReceipt) -> Bool {
        if hasVoted(receipt) { return false }
        if let decided = sessionDecisions[receipt.requestId] { return decided }
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        let show = count.isMultiple(of: askEvery)
        sessionDecisions[receipt.requestId] = show
        return show
    }

    static func markVoted(_ receipt: LLMFeedbackReceipt) {
        sessionDecisions[receipt.requestId] = false
        append(receipt.requestId, to: votedRequestKey)
        append(contentKey(for: receipt), to: votedContentKey)
    }

    private static func hasVoted(_ receipt: LLMFeedbackReceipt) -> Bool {
        let requests = Set(UserDefaults.standard.stringArray(forKey: votedRequestKey) ?? [])
        if requests.contains(receipt.requestId) { return true }
        let contents = Set(UserDefaults.standard.stringArray(forKey: votedContentKey) ?? [])
        return contents.contains(contentKey(for: receipt))
    }

    private static func contentKey(for receipt: LLMFeedbackReceipt) -> String {
        let payload: Any
        if JSONSerialization.isValidJSONObject(receipt.inputObject) {
            payload = receipt.inputObject
        } else {
            payload = receipt.requestId
        }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(receipt.feature)|\(hex)"
    }

    private static func append(_ value: String, to key: String) {
        var items = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !items.contains(value) else { return }
        items.append(value)
        if items.count > 400 {
            items.removeFirst(items.count - 400)
        }
        UserDefaults.standard.set(items, forKey: key)
    }
}

/// Glass thumbs for one LLM result. Hidden until `present`. The first tap locks the rating.
final class LLMFeedbackRow: UIView {

    static let diameter: CGFloat = 36
    static let thumbGap: CGFloat = 8
    static var clusterWidth: CGFloat { diameter * 2 + thumbGap }

    var onVisibilityChange: (() -> Void)?

    private let containerEffect: UIGlassContainerEffect = {
        let effect = UIGlassContainerEffect()
        effect.spacing = 8
        return effect
    }()
    private lazy var glassContainer = UIVisualEffectView(effect: containerEffect)
    private let downGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let upGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let downButton = UIButton(type: .system)
    private let upButton = UIButton(type: .system)

    private var receipt: LLMFeedbackReceipt?
    private var locked = false
    private var hideTask: Task<Void, Never>?
    private var isReasonSheetPresented = false
    private var thumbsSeparated = false
    private var collapsedToUp = false
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    private static let upSymbol = "hand.thumbsup"
    private static let downSymbol = "hand.thumbsdown"

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: widthConstraint.constant, height: heightConstraint.constant)
    }

    func present(_ receipt: LLMFeedbackReceipt?) {
        guard let receipt, LLMFeedbackPrompt.shouldOffer(receipt) else {
            if !isHidden { dismiss() }
            return
        }
        if self.receipt?.requestId == receipt.requestId, !isHidden, alpha > 0.9 {
            return
        }
        hideTask?.cancel()
        isReasonSheetPresented = false
        self.receipt = receipt
        locked = false
        alpha = 1
        isHidden = false
        downButton.isUserInteractionEnabled = true
        upButton.isUserInteractionEnabled = true
        downGlass.alpha = 1
        upGlass.alpha = 1
        collapsedToUp = false
        styleThumb(downButton, symbol: Self.downSymbol, tint: .secondaryLabel)
        styleThumb(upButton, symbol: Self.upSymbol, tint: .secondaryLabel)
        thumbsSeparated = false
        onVisibilityChange?()
        setNeedsLayout()
        layoutIfNeeded()
        applyThumbFrames(separated: false)
        UIView.animate(
            withDuration: 0.52,
            delay: 0.02,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.thumbsSeparated = true
            self.applyThumbFrames(separated: true)
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        isReasonSheetPresented = false
        receipt = nil
        locked = false
        alpha = 1
        thumbsSeparated = false
        collapsedToUp = false
        downGlass.alpha = 1
        upGlass.alpha = 1
        isHidden = true
        onVisibilityChange?()
    }

    private func setup() {
        isHidden = true
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        widthConstraint = widthAnchor.constraint(equalToConstant: Self.clusterWidth)
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.diameter)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        glassContainer.translatesAutoresizingMaskIntoConstraints = true
        glassContainer.clipsToBounds = false
        downGlass.translatesAutoresizingMaskIntoConstraints = true
        upGlass.translatesAutoresizingMaskIntoConstraints = true
        let downEffect = UIGlassEffect(style: .regular)
        downEffect.isInteractive = true
        downGlass.effect = downEffect
        let upEffect = UIGlassEffect(style: .regular)
        upEffect.isInteractive = true
        upGlass.effect = upEffect

        configureThumb(downButton, symbol: Self.downSymbol, label: "Not helpful", tint: .secondaryLabel, action: #selector(downTapped))
        configureThumb(upButton, symbol: Self.upSymbol, label: "Helpful", tint: .secondaryLabel, action: #selector(upTapped))
        pin(downButton, in: downGlass)
        pin(upButton, in: upGlass)
        glassContainer.contentView.addSubview(downGlass)
        glassContainer.contentView.addSubview(upGlass)
        addSubview(glassContainer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassContainer.frame = CGRect(
            x: bounds.width - Self.clusterWidth,
            y: bounds.height - Self.diameter,
            width: Self.clusterWidth,
            height: Self.diameter
        )
        let radius = Self.diameter / 2
        downGlass.cornerConfiguration = .corners(radius: .fixed(radius))
        upGlass.cornerConfiguration = .corners(radius: .fixed(radius))
        applyThumbFrames(separated: thumbsSeparated)
    }

    private func applyThumbFrames(separated: Bool) {
        if collapsedToUp {
            downGlass.alpha = 0
            upGlass.frame = CGRect(
                x: glassContainer.bounds.width - Self.diameter,
                y: 0,
                width: Self.diameter,
                height: Self.diameter
            )
            return
        }
        let travel: CGFloat = separated ? (Self.diameter + Self.thumbGap) / 2 : 0
        let mid = glassContainer.bounds.midX
        downGlass.frame = CGRect(
            x: mid - Self.diameter / 2 - travel,
            y: 0,
            width: Self.diameter,
            height: Self.diameter
        )
        upGlass.frame = CGRect(
            x: mid - Self.diameter / 2 + travel,
            y: 0,
            width: Self.diameter,
            height: Self.diameter
        )
    }

    private func pin(_ button: UIButton, in glass: UIVisualEffectView) {
        button.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            button.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
        ])
    }

    private func configureThumb(_ button: UIButton, symbol: String, label: String, tint: UIColor, action: Selector) {
        var config = UIButton.Configuration.plain()
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = config
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        styleThumb(button, symbol: symbol, tint: tint)
    }

    private func styleThumb(_ button: UIButton, symbol: String, tint: UIColor) {
        var config = button.configuration ?? .plain()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = tint
        button.configuration = config
    }

    @objc private func upTapped() {
        guard !locked else { return }
        lock()
        styleThumb(upButton, symbol: Self.upSymbol + ".fill", tint: .label)
        send(rating: .up, reason: nil)
        showVoteToast()
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.collapsedToUp = true
            self.thumbsSeparated = false
            self.applyThumbFrames(separated: false)
        }
        scheduleHide(after: 2.6)
    }

    @objc private func downTapped() {
        guard !locked else { return }
        lock()
        hideTask?.cancel()
        isReasonSheetPresented = true
        styleThumb(downButton, symbol: Self.downSymbol + ".fill", tint: .label)
        send(rating: .down, reason: nil)
        presentReasonSheet()
    }

    private func presentReasonSheet() {
        guard let presenter = presentingController() else {
            finishReasonPrompt()
            return
        }
        let picker = LLMFeedbackReasonSheetController()
        picker.onFinish = { [weak self] reason in
            if let reason {
                self?.send(rating: .down, reason: reason)
            }
            self?.showVoteToast()
            self?.finishReasonPrompt()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        nav.modalTransitionStyle = .coverVertical
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: UISheetPresentationController.Detent.Identifier("llmReason")) { _ in 292 },
            ]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        presenter.present(nav, animated: true)
    }

    private func finishReasonPrompt() {
        guard isReasonSheetPresented else { return }
        isReasonSheetPresented = false
        scheduleHide(after: 0.25)
    }

    private func lock() {
        locked = true
        upButton.isUserInteractionEnabled = false
        downButton.isUserInteractionEnabled = false
    }

    private func scheduleHide(after seconds: TimeInterval) {
        guard !isReasonSheetPresented else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.fadeOut()
            }
        }
    }

    private func fadeOut() {
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
            self.thumbsSeparated = false
            self.applyThumbFrames(separated: false)
        } completion: { [weak self] _ in
            self?.dismiss()
        }
    }

    private func send(rating: LLMFeedbackRating, reason: LLMFeedbackReason?) {
        guard let receipt else { return }
        LLMFeedbackPrompt.markVoted(receipt)
        Task {
            await LLMGatewayClient.postFeedback(receipt, rating: rating, reason: reason)
        }
    }

    private func showVoteToast() {
        nearestViewController()?.showToast(text: "Thanks for the feedback")
    }

    private func presentingController() -> UIViewController? {
        guard var presenter = nearestViewController() else { return nil }
        while let shown = presenter.presentedViewController, !shown.isBeingDismissed {
            presenter = shown
        }
        return presenter
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

private final class LLMFeedbackReasonSheetController: UIViewController {
    var onFinish: ((LLMFeedbackReason?) -> Void)?
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "What was off?"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for reason in LLMFeedbackReason.allCases {
            var config = UIButton.Configuration.gray()
            config.title = reason.title
            config.cornerStyle = .large
            config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.pick(reason)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            finish(nil)
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func pick(_ reason: LLMFeedbackReason) {
        finish(reason)
        dismiss(animated: true)
    }

    private func finish(_ reason: LLMFeedbackReason?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(reason)
    }
}
