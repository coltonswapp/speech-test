import UIKit

final class OnboardingSliderViewController: OnboardingViewController {

    private let config: SliderStepConfig
    private let levelTitleLabel = FuriganaTranscriptLabel()
    private let levelDescriptionLabel = UILabel()
    private var slider: OnboardingDetentSliderView!
    private var levelBubble: DialogueJapaneseBubbleView!
    private var selectedIndex = 0

    private static let levelTitleFont = UIFont.systemFont(ofSize: 22, weight: .bold)

    init(config: SliderStepConfig) {
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
        applyLevel(at: 0)
    }

    override func setupContent() {
        levelTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        levelTitleLabel.numberOfLines = 1
        levelTitleLabel.textAlignment = .center

        levelBubble = DialogueJapaneseBubbleView(label: levelTitleLabel)
        levelBubble.setBackgroundStyle(.glass)
        levelBubble.setEmphasis(1)
        levelBubble.setUnderglowConfiguration(.default)

        levelDescriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        levelDescriptionLabel.textAlignment = .center
        levelDescriptionLabel.textColor = .secondaryLabel
        levelDescriptionLabel.numberOfLines = 0
        levelDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        slider = OnboardingDetentSliderView(detentCount: max(config.levels.count, 2))
        slider.onIndexChanged = { [weak self] index in
            self?.applyLevel(at: index)
            self?.persistCurrentLevel()
        }

        view.addSubview(levelBubble)
        view.addSubview(levelDescriptionLabel)
        view.addSubview(slider)

        NSLayoutConstraint.activate([
            levelBubble.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 28),
            levelBubble.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            levelBubble.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 48),
            levelBubble.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -48),

            levelDescriptionLabel.topAnchor.constraint(equalTo: levelBubble.bottomAnchor, constant: 20),
            levelDescriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            levelDescriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            slider.topAnchor.constraint(equalTo: levelDescriptionLabel.bottomAnchor, constant: 36),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func ctaTapped() {
        persistCurrentLevel()
        coordinator?.next()
    }

    private func applyLevel(at index: Int) {
        guard config.levels.indices.contains(index) else { return }
        selectedIndex = index
        let level = config.levels[index]
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: levelTitleLabel,
            text: level.title,
            font: Self.levelTitleFont,
            textColor: .label
        )
        levelDescriptionLabel.text = level.description
        levelBubble?.invalidateIntrinsicContentSize()
        levelBubble?.setNeedsLayout()
    }

    private func persistCurrentLevel() {
        guard config.levels.indices.contains(selectedIndex) else { return }
        let level = config.levels[selectedIndex]
        coordinator?.updateSliderLevel(level.value ?? level.title)
    }
}
