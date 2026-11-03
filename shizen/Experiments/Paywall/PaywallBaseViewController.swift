//
//  PaywallBaseViewController.swift
//  shizen
//
//  Shared plumbing for every custom paywall variant: load the offering, track an
//  impression on each appearance, hold the selected package, and run purchase /
//  restore / close. Subclasses only build UI in `render(_:)` and react in
//  `selectedPackageDidChange(animated:)`.
//

import UIKit

class PaywallBaseViewController: UIViewController {
    let provider: PaywallProviding
    let placement: String?
    private(set) var offering: PaywallOffering?
    private(set) var selectedPackage: PaywallPackage?
    /// Subclasses assign this so purchase can show its spinner.
    var ctaButton: PaywallCTAButton?

    private var isOnScreen = false
    private let selectionHaptics = UISelectionFeedbackGenerator()
    private var firstAppearedAt: Date?
    /// `reason` on `paywall_dismissed`; set by whatever closes the paywall.
    private var exitReason = "system"

    init(provider: PaywallProviding, placement: String? = "onboarding") {
        self.provider = provider
        self.placement = placement
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadOffering() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        if firstAppearedAt == nil { firstAppearedAt = Date() }
        // Every appearance counts, so experiment results include returning viewers.
        if let offering { trackImpression(offering) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isOnScreen = false
        if isBeingDismissed || isMovingFromParent {
            trackFunnel(.paywallDismissed, ["reason": exitReason])
        }
    }

    // MARK: Subclass hooks

    /// `variant` on `paywall_viewed`; nil keeps a variant out of funnel analytics.
    var analyticsVariant: String? { nil }

    /// Extra properties a variant adds to the CTA tap and dismiss (e.g. carousel state).
    var analyticsExtraProperties: [String: Any] { [:] }

    func render(_ offering: PaywallOffering) {}

    func selectedPackageDidChange(animated: Bool) {}

    // MARK: Selection

    func select(_ package: PaywallPackage) {
        guard package != selectedPackage else { return }
        selectedPackage = package
        trackFunnel(.paywallPlanSelected, Self.properties(of: package))
        selectionHaptics.selectionChanged()
        selectedPackageDidChange(animated: true)
    }

    /// Wires plan rows or tiles to selection.
    func bind(_ rows: [any PaywallPlanControl]) {
        for row in rows {
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let row else { return }
                self?.select(row.package)
            }, for: .touchUpInside)
        }
    }

    // MARK: Loading

    /// Funnel events carry the variant, offering, source, and time on screen. Variants
    /// without `analyticsVariant` stay out of analytics, same as `paywall_viewed`.
    func trackFunnel(_ event: Analytics.Event, _ properties: [String: Any] = [:]) {
        guard let analyticsVariant else { return }
        var all = properties
        all["variant"] = analyticsVariant
        all["offering_id"] = offering?.identifier
        all["source"] = placement ?? "unknown"
        if let firstAppearedAt {
            all["seconds_on_screen"] = Int(Date().timeIntervalSince(firstAppearedAt).rounded())
        }
        if event == .paywallDismissed {
            all.merge(analyticsExtraProperties) { current, _ in current }
        }
        Analytics.track(event, all)
    }

    private static func properties(of package: PaywallPackage) -> [String: Any] {
        let period: String = switch package.period {
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .annual: "annual"
        }
        return [
            "package_id": package.identifier,
            "product_id": package.productIdentifier,
            "period": period,
            "price": NSDecimalNumber(decimal: package.price).doubleValue,
            "currency": package.currencyCode,
            "has_trial": package.hasTrial,
        ]
    }

    private func trackImpression(_ offering: PaywallOffering) {
        provider.trackImpression(offering: offering)
        if let analyticsVariant {
            Analytics.paywallViewed(variant: analyticsVariant, offeringId: offering.identifier, source: placement ?? "unknown")
        }
    }

    private func loadOffering() async {
        do {
            let offering = try await provider.fetchOffering(placement: placement)
            self.offering = offering
            selectedPackage = offering.defaultPackage
            render(offering)
            selectedPackageDidChange(animated: false)
            if isOnScreen { trackImpression(offering) }
        } catch {
            presentAlert(title: "Couldn't load plans", message: error.localizedDescription, dismissAfter: true)
        }
    }

    // MARK: Actions

    @objc func closeTapped() {
        exitReason = "close"
        dismiss(animated: true)
    }

    /// Intent only. `trial_started` / `purchased` come from RevenueCat via `PurchaseAnalytics`.
    @objc func purchaseTapped() {
        guard let package = selectedPackage else { return }
        trackFunnel(.paywallCTATapped, Self.properties(of: package).merging(analyticsExtraProperties) { _, new in new })
        ctaButton?.isLoading = true
        Task {
            defer { ctaButton?.isLoading = false }
            do {
                let purchased = try await provider.purchase(package)
                guard purchased else {
                    trackFunnel(.purchaseCancelled, Self.properties(of: package))
                    return
                }
                exitReason = "purchased"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                presentAlert(
                    title: "Welcome to Pro",
                    message: "Mock purchase of \(package.productIdentifier) succeeded.",
                    dismissAfter: true
                )
            } catch {
                var properties = Self.properties(of: package)
                properties["error_domain"] = (error as NSError).domain
                properties["error_code"] = (error as NSError).code
                trackFunnel(.purchaseFailed, properties)
                presentAlert(title: "Purchase failed", message: error.localizedDescription)
            }
        }
    }

    @objc func restoreTapped() {
        Task {
            do {
                let restored = try await provider.restorePurchases()
                trackFunnel(.restoreCompleted, ["result": restored ? "restored" : "nothing"])
                if restored { exitReason = "restored" }
                presentAlert(
                    title: restored ? "Purchases restored" : "Nothing to restore",
                    message: restored ? nil : "No active subscription was found for this Apple ID.",
                    dismissAfter: restored
                )
            } catch {
                trackFunnel(.restoreCompleted, ["result": "failed"])
                presentAlert(title: "Restore failed", message: error.localizedDescription)
            }
        }
    }

    private func presentAlert(title: String, message: String?, dismissAfter: Bool = false) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if dismissAfter { self?.dismiss(animated: true) }
        })
        present(alert, animated: true)
    }

    // MARK: Layout helpers

    let scrollView = UIScrollView()

    /// Scrolling `content` above a `footer` pinned to the bottom safe area.
    func installScrollLayout(content: UIView, footer: UIView, horizontalInset: CGFloat = 24, topInset: CGFloat = 64) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        content.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: topInset),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -horizontalInset),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    /// Glass close (leading) and optional Restore (trailing) buttons over everything.
    func installTopBar(tint: UIColor, showsRestore: Bool = true) {
        var closeConfig = UIButton.Configuration.glass()
        closeConfig.image = UIImage(systemName: "xmark")
        closeConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        closeConfig.baseForegroundColor = tint
        closeConfig.cornerStyle = .capsule
        let close = UIButton(configuration: closeConfig)
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
        ])

        guard showsRestore else { return }
        var restoreConfig = UIButton.Configuration.glass()
        restoreConfig.title = "Restore"
        restoreConfig.baseForegroundColor = tint
        restoreConfig.cornerStyle = .capsule
        restoreConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 15, weight: .medium)
            return attributes
        }
        let restore = UIButton(configuration: restoreConfig)
        restore.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        restore.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(restore)
        NSLayoutConstraint.activate([
            restore.heightAnchor.constraint(equalToConstant: 44),
            restore.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            restore.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
    }

    func makeCTA(background: UIColor, foreground: UIColor) -> PaywallCTAButton {
        let button = PaywallCTAButton(background: background, foreground: foreground)
        button.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        ctaButton = button
        return button
    }

    func makeFinePrintLabel(color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    /// "Terms · Restore · Privacy" row.
    func makeLegalLinks(color: UIColor, includesRestore: Bool = false, underlined: Bool = false) -> UIStackView {
        var titles = ["Terms"]
        if includesRestore { titles.append("Restore Purchase") }
        titles.append("Privacy")

        let stack = UIStackView()
        stack.alignment = .center
        stack.spacing = 18
        for title in titles {
            var config = UIButton.Configuration.plain()
            config.contentInsets = .zero
            var attributes = AttributeContainer()
            attributes.font = UIFont.systemFont(ofSize: 12)
            if underlined { attributes.underlineStyle = .single }
            config.attributedTitle = AttributedString(title, attributes: attributes)
            config.baseForegroundColor = color
            let button = UIButton(configuration: config)
            if title.hasPrefix("Restore") {
                button.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
            }
            stack.addArrangedSubview(button)
        }
        return stack
    }
}
