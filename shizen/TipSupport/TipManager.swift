import UIKit

// MARK: - Display Rules

struct TipContext {
    let currentDate: Date
    let currentScreen: String?
    let userActionCounts: [String: Int]
    let screenVisitCounts: [String: Int]
    let customData: [String: Any]
}

protocol TipDisplayRule {
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool
}

/// Show a tip only after N days have elapsed since first app launch.
struct TimeBasedRule: TipDisplayRule {
    let minimumInterval: TimeInterval
    let startDateKey: String

    init(minimumDays: Int, startDateKey: String = "tip_first_launch_date") {
        self.minimumInterval = TimeInterval(minimumDays * 86400)
        self.startDateKey = startDateKey
    }

    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        let start = UserDefaults.standard.object(forKey: startDateKey) as? Date ?? Date()
        return context.currentDate.timeIntervalSince(start) >= minimumInterval
    }
}

/// Show a tip only after the user has visited a named screen at least N times.
struct VisitCountRule: TipDisplayRule {
    let screenName: String
    let minimumVisits: Int

    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        (context.screenVisitCounts[screenName] ?? 0) >= minimumVisits
    }
}

/// Show a tip only after a named user action has occurred at least N times.
struct UserActionRule: TipDisplayRule {
    let actionName: String
    let minimumCount: Int

    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        (context.userActionCounts[actionName] ?? 0) >= minimumCount
    }
}

/// Show a tip based on a custom closure condition.
struct ConditionalRule: TipDisplayRule {
    let condition: (String, TipContext) -> Bool

    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        condition(tipId, context)
    }
}

// MARK: - TipManager

/// Singleton that shows, tracks, and persists tooltip state.
/// All public methods are @MainActor-safe.
class TipManager {
    static let shared = TipManager()

    // MARK: Persistence Keys
    private let dismissedKey = "TipManager_DismissedTips"
    private let screenVisitsKey = "TipManager_ScreenVisits"
    private let userActionsKey = "TipManager_UserActions"
    private let firstLaunchKey = "tip_first_launch_date"

    // MARK: State
    private var displayRules: [String: [TipDisplayRule]] = [:]
    private var activeTipViews: [TipView] = []
    private var sequentialTasks: [String: Task<Void, Never>] = [:]

    private init() {
        if UserDefaults.standard.object(forKey: firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
        }
    }

    // MARK: - Persistence Helpers

    private var dismissedTips: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: dismissedKey) }
    }

    private var screenVisitCounts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: screenVisitsKey) as? [String: Int] ?? [:]
    }

    private var userActionCounts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: userActionsKey) as? [String: Int] ?? [:]
    }

    // MARK: - Rule Management

    func addRule(_ rule: TipDisplayRule, for tipId: String) {
        displayRules[tipId, default: []].append(rule)
    }

    func clearRules(for tipId: String) {
        displayRules.removeValue(forKey: tipId)
    }

    // MARK: - Tracking

    func trackScreenVisit(_ screenName: String) {
        var counts = screenVisitCounts
        counts[screenName] = (counts[screenName] ?? 0) + 1
        UserDefaults.standard.set(counts, forKey: screenVisitsKey)
    }

    func trackUserAction(_ actionName: String) {
        var counts = userActionCounts
        counts[actionName] = (counts[actionName] ?? 0) + 1
        UserDefaults.standard.set(counts, forKey: userActionsKey)
    }

    // MARK: - State Queries

    func shouldShowTip(_ tip: TipModel, currentScreen: String? = nil, customData: [String: Any] = [:]) -> Bool {
        guard !dismissedTips.contains(tip.id) else { return false }
        let rules = displayRules[tip.id] ?? []
        guard !rules.isEmpty else { return true }
        let context = TipContext(
            currentDate: Date(),
            currentScreen: currentScreen,
            userActionCounts: userActionCounts,
            screenVisitCounts: screenVisitCounts,
            customData: customData
        )
        return rules.allSatisfy { $0.shouldDisplay(for: tip.id, context: context) }
    }

    func isShowingTip(_ tip: TipModel) -> Bool {
        activeTipViews.contains { $0.tipId == tip.id }
    }

    // MARK: - Dismiss

    func dismissTip(_ tip: TipModel) {
        var set = dismissedTips
        set.insert(tip.id)
        dismissedTips = set
        dismissActiveTipView(for: tip.id)
    }

    func dismissTip(_ tip: TipModel, afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dismissTip(tip)
        }
    }

    func dismissAllActiveTips() {
        activeTipViews.forEach { animateOut($0) }
    }

    func resetAllTips() {
        dismissedTips = []
        UserDefaults.standard.removeObject(forKey: screenVisitsKey)
        UserDefaults.standard.removeObject(forKey: userActionsKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchKey)
        UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
    }

    // MARK: - Show (single tip)

    func showTip(_ tip: TipModel,
                 sourceView: UIView,
                 in viewController: UIViewController,
                 arrowEdge: TipArrowEdge = .bottom,
                 offset: CGPoint = CGPoint(x: 0, y: 8),
                 centerHorizontally: Bool = false) {

        let tipView = TipView(tip: tip, arrowEdge: arrowEdge)
        tipView.setSourceView(sourceView)
        tipView.translatesAutoresizingMaskIntoConstraints = false
        tipView.setDismissHandler { [weak self, weak tipView] in
            guard let self, let tipView else { return }
            self.dismissTip(tip)
            self.activeTipViews.removeAll { $0 === tipView }
        }

        activeTipViews.append(tipView)
        viewController.view.addSubview(tipView)
        applyConstraints(tipView, sourceView: sourceView, in: viewController, arrowEdge: arrowEdge, offset: offset, centerHorizontally: centerHorizontally)
        viewController.view.layoutIfNeeded()
        tipView.updateArrowPosition()
        tipView.showWithAnimation()
    }

    // MARK: - Sequential Tips

    func showTipsSequentially(
        _ configs: [(tip: TipModel, sourceView: UIView, arrowEdge: TipArrowEdge, offset: CGPoint)],
        in viewController: UIViewController,
        sequenceId: String
    ) {
        stopSequence(sequenceId)
        sequentialTasks[sequenceId] = Task { @MainActor in
            for config in configs {
                guard !Task.isCancelled else { break }
                if shouldShowTip(config.tip) {
                    await showAndWait(config.tip, sourceView: config.sourceView, arrowEdge: config.arrowEdge, offset: config.offset, in: viewController)
                }
            }
        }
    }

    func stopSequence(_ sequenceId: String) {
        sequentialTasks[sequenceId]?.cancel()
        sequentialTasks.removeValue(forKey: sequenceId)
    }

    func stopAllSequences() {
        sequentialTasks.values.forEach { $0.cancel() }
        sequentialTasks.removeAll()
    }

    // MARK: - Private Helpers

    private func dismissActiveTipView(for tipId: String) {
        guard let tipView = activeTipViews.first(where: { $0.tipId == tipId }) else { return }
        animateOut(tipView)
    }

    private func animateOut(_ tipView: TipView) {
        activeTipViews.removeAll { $0 === tipView }
        tipView.dismissWithAnimation()
    }

    private func showAndWait(
        _ tip: TipModel,
        sourceView: UIView,
        arrowEdge: TipArrowEdge,
        offset: CGPoint,
        in viewController: UIViewController
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else { continuation.resume(); return }

                let tipView = TipView(tip: tip, arrowEdge: arrowEdge)
                tipView.translatesAutoresizingMaskIntoConstraints = false
                tipView.setSourceView(sourceView)
                tipView.setDismissHandler { [weak self, weak tipView] in
                    guard let self, let tipView else { return }
                    self.dismissTip(tip)
                    self.activeTipViews.removeAll { $0 === tipView }
                    continuation.resume()
                }

                viewController.view.addSubview(tipView)
                self.applyConstraints(tipView, sourceView: sourceView, in: viewController, arrowEdge: arrowEdge, offset: offset)
                viewController.view.layoutIfNeeded()
                tipView.updateArrowPosition()
                tipView.showWithAnimation()
                self.activeTipViews.append(tipView)
            }
        }
    }

    // MARK: - Constraint Setup

    func applyConstraints(
        _ tipView: UIView,
        sourceView: UIView,
        in viewController: UIViewController,
        arrowEdge: TipArrowEdge,
        offset: CGPoint,
        centerHorizontally: Bool = false
    ) {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let maxWidth: CGFloat = 300
        var constraints: [NSLayoutConstraint] = []

        switch arrowEdge {
        case .top, .bottom:
            if isIPad {
                constraints.append(tipView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth))
            } else {
                constraints.append(tipView.widthAnchor.constraint(equalTo: viewController.view.widthAnchor, multiplier: 0.8))
            }

            let centerX: NSLayoutConstraint
            if centerHorizontally {
                centerX = tipView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor)
            } else {
                let sourceFrame = sourceView.superview?.convert(sourceView.frame, to: viewController.view) ?? .zero
                let vcWidth = viewController.view.bounds.width
                let tooltipWidth = isIPad ? min(vcWidth * 0.8, maxWidth) : vcWidth * 0.8
                let ideal = sourceFrame.midX
                let lo = tooltipWidth / 2 + 8
                let hi = vcWidth - tooltipWidth / 2 - 8
                let clamped = max(lo, min(hi, ideal))
                centerX = tipView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: clamped - vcWidth / 2)
            }

            if arrowEdge == .top {
                constraints += [centerX, tipView.bottomAnchor.constraint(equalTo: sourceView.topAnchor, constant: offset.y)]
            } else {
                constraints += [centerX, tipView.topAnchor.constraint(equalTo: sourceView.bottomAnchor, constant: offset.y)]
            }

        case .leading:
            constraints = [
                tipView.leadingAnchor.constraint(equalTo: sourceView.trailingAnchor, constant: offset.x),
                tipView.centerYAnchor.constraint(equalTo: sourceView.centerYAnchor, constant: offset.y)
            ]
            if isIPad { constraints.append(tipView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)) }

        case .trailing:
            constraints = [
                tipView.trailingAnchor.constraint(equalTo: sourceView.leadingAnchor, constant: -offset.x),
                tipView.centerYAnchor.constraint(equalTo: sourceView.centerYAnchor, constant: offset.y)
            ]
            if isIPad {
                constraints.append(tipView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth))
            } else {
                constraints.append(tipView.widthAnchor.constraint(equalTo: viewController.view.widthAnchor, multiplier: 0.8))
            }
        }

        // Keep tooltip inside safe area
        constraints += [
            tipView.topAnchor.constraint(greaterThanOrEqualTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tipView.bottomAnchor.constraint(lessThanOrEqualTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            tipView.leadingAnchor.constraint(greaterThanOrEqualTo: viewController.view.leadingAnchor, constant: 8),
            tipView.trailingAnchor.constraint(lessThanOrEqualTo: viewController.view.trailingAnchor, constant: -8)
        ]

        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - UIViewController Convenience

extension UIViewController {
    func showTip(_ tip: TipModel, for view: UIView, arrowEdge: TipArrowEdge = .bottom, offset: CGPoint = CGPoint(x: 0, y: 8), centerHorizontally: Bool = false) {
        TipManager.shared.showTip(tip, sourceView: view, in: self, arrowEdge: arrowEdge, offset: offset, centerHorizontally: centerHorizontally)
    }

    func trackScreenVisit(_ screenName: String? = nil) {
        TipManager.shared.trackScreenVisit(screenName ?? String(describing: type(of: self)))
    }

    func trackUserAction(_ actionName: String) {
        TipManager.shared.trackUserAction(actionName)
    }

    func showTipsSequentially(_ configs: [(tip: TipModel, sourceView: UIView, arrowEdge: TipArrowEdge, offset: CGPoint)], sequenceId: String) {
        TipManager.shared.showTipsSequentially(configs, in: self, sequenceId: sequenceId)
    }

    func stopTipSequence(_ sequenceId: String) {
        TipManager.shared.stopSequence(sequenceId)
    }
}
