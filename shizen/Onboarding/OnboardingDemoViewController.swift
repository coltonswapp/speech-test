import UIKit

final class OnboardingDemoViewController: OnboardingViewController {

    private let config: DemoStepConfig
    private var inspectViewController: SentenceScrubExperimentViewController?

    private static let conversationFont = UIFont.systemFont(ofSize: 20, weight: .medium)

    init(config: DemoStepConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        setupOnboarding(title: config.title, subtitle: config.subtitle)
        super.viewDidLoad()
        addCTAButton(title: config.ctaText ?? "Next")
    }

    override func setupContent() {
        switch config.variant {
        case .bars:
            installConversation()
        case .inspect:
            installSentenceScrub()
        }
    }

    private func installConversation() {
        let lines: [(japanese: String, english: String, side: DialogueSpeakerSide)] = [
            ("いらっしゃいませ。", "Welcome.", .leading),
            ("これをください。", "I'll take this, please.", .trailing),
            ("お釣りは五十円です。", "Your change is 50 yen.", .leading),
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        for line in lines {
            stack.addArrangedSubview(makeConversationRow(
                japanese: line.japanese,
                english: line.english,
                side: line.side
            ))
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -80
            ),
        ])
    }

    private func makeConversationRow(
        japanese: String,
        english: String,
        side: DialogueSpeakerSide
    ) -> UIView {
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: japanese,
            font: Self.conversationFont,
            side: side,
            showsTail: true
        )
        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let englishLabel = UILabel()
        englishLabel.text = english
        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textColor = .secondaryLabel
        englishLabel.numberOfLines = 0
        englishLabel.textAlignment = side == .trailing ? .right : .left

        let column = UIStackView(arrangedSubviews: [bubble, englishLabel])
        column.axis = .vertical
        column.spacing = 4
        column.alignment = side == .trailing ? .trailing : .leading

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        if side == .trailing {
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
        }
        row.addArrangedSubview(column)
        bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.86).isActive = true
        return row
    }

    private func installSentenceScrub() {
        let scrub = SentenceScrubExperimentViewController(
            sentence: "お釣りは五十円です。",
            englishTranslation: "Your change is 50 yen."
        )
        inspectViewController = scrub
        addChild(scrub)
        scrub.view.translatesAutoresizingMaskIntoConstraints = false
        scrub.view.backgroundColor = ExperimentPalette.pageBackground
        view.addSubview(scrub.view)

        NSLayoutConstraint.activate([
            scrub.view.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 8),
            scrub.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrub.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrub.view.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -80
            ),
        ])
        scrub.didMove(toParent: self)
    }
}
