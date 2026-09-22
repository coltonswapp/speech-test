import UIKit

final class OnboardingPlanViewController: OnboardingViewController {

    private let config: BasicStepConfig
    private let card = OnboardingSummaryCard()

    init(config: BasicStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: config.title ?? "Here's your start.", subtitle: config.subtitle)
        super.viewDidLoad()
        addCTAButton(title: config.ctaText ?? "Next")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        card.text = coordinator?.journeySummaryLine() ?? config.subtitle
    }

    override func setupContent() {
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 28),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}

final class OnboardingPaywallViewController: OnboardingViewController {

    private let config: BasicStepConfig
    private var cards: [OnboardingSummaryCard] = []
    private var selectedIndex = 0

    init(config: BasicStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: config.title ?? "Listen in the building.", subtitle: config.subtitle)
        super.viewDidLoad()
        addCTAButton(title: config.ctaText ?? "Start free trial")
    }

    override func setupContent() {
        let plans = [
            "Yearly · best value",
            "Monthly",
        ]
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        for (index, title) in plans.enumerated() {
            let card = OnboardingSummaryCard()
            card.text = title
            card.tag = index
            card.addTarget(self, action: #selector(planTapped(_:)), for: .touchUpInside)
            cards.append(card)
            stack.addArrangedSubview(card)
        }
        applySelection()

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc private func planTapped(_ sender: OnboardingSummaryCard) {
        selectedIndex = sender.tag
        applySelection()
        playSelectionHaptic()
    }

    private func applySelection() {
        for card in cards {
            card.isChosen = card.tag == selectedIndex
        }
    }
}

final class OnboardingAuthStepViewController: OnboardingViewController {

    private let config: BasicStepConfig
    private let skipButton = UIButton(type: .system)

    init(config: BasicStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: config.title ?? "Save your progress.", subtitle: config.subtitle)
        super.viewDidLoad()
        addCTAButton(title: config.ctaText ?? "Continue with Apple")

        skipButton.setTitle("Skip for now", for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        skipButton.setTitleColor(.secondaryLabel, for: .normal)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skipButton)

        NSLayoutConstraint.activate([
            skipButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            skipButton.bottomAnchor.constraint(equalTo: contentBottomAnchor, constant: -12),
        ])
    }

    override func setupContent() {}

    override func ctaTapped() {
        playSelectionHaptic()
        coordinator?.setPendingProvider(.apple)
        coordinator?.next()
    }

    @objc private func skipTapped() {
        playSelectionHaptic()
        coordinator?.setPendingProvider(nil)
        coordinator?.next()
    }
}

final class OnboardingSummaryCard: UIControl {

    var text: String? {
        didSet { titleLabel.text = text }
    }

    var isChosen: Bool = false {
        didSet { applyChrome() }
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            heightAnchor.constraint(greaterThanOrEqualToConstant: OnboardingOptionCell.preferredHeight),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: OnboardingSummaryCard, _) in
            card.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyChrome() {
        layer.borderWidth = isChosen ? ExperimentCardStroke.emphasisWidth : ExperimentCardStroke.normalWidth
        layer.borderColor = (isChosen ? ExperimentPalette.highlightBorder : ExperimentPalette.cardBorder).cgColor
        backgroundColor = isChosen ? ExperimentPalette.highlightFill : ExperimentPalette.cardSurface
    }
}
