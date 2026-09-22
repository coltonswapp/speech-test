import NNKit
import UIKit

final class OnboardingSliderViewController: OnboardingViewController {

    private let config: SliderStepConfig
    private let levelTitleLabel = FuriganaTranscriptLabel()
    private let levelDescriptionLabel = UILabel()
    private var slider: OnboardingDetentSliderView!
    private var levelBubble: DialogueJapaneseBubbleView!
    private var descriptionHeightConstraint: NSLayoutConstraint?
    private var reservedDescriptionWidth: CGFloat = 0
    private var selectedIndex = 0
    private var hasPresentedInitialLevel = false

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
            guard let self else { return }
            self.applyLevel(at: index)
            self.persistCurrentLevel()
            self.explodeForSliderDetent(index)
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reserveDescriptionHeight()
    }

    /// Keep the slider put when a shorter description wraps to fewer lines.
    private func reserveDescriptionHeight() {
        let width = levelDescriptionLabel.bounds.width
        guard width > 1, abs(width - reservedDescriptionWidth) > 0.5 else { return }
        reservedDescriptionWidth = width

        let font = levelDescriptionLabel.font ?? .preferredFont(forTextStyle: .subheadline)
        let tallest = config.levels.map { level in
            ceil((level.description as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height)
        }.max() ?? 0

        if let descriptionHeightConstraint {
            descriptionHeightConstraint.constant = tallest
        } else {
            let constraint = levelDescriptionLabel.heightAnchor.constraint(equalToConstant: tallest)
            constraint.isActive = true
            descriptionHeightConstraint = constraint
        }
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
        if hasPresentedInitialLevel {
            bounceLevelTitle()
        }
        hasPresentedInitialLevel = true
    }

    private func bounceLevelTitle() {
        guard let levelBubble else { return }
        levelBubble.layer.removeAnimation(forKey: "levelTitleBounce")
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, -14, 3, 0]
        bounce.keyTimes = [0, 0.38, 0.72, 1]
        bounce.duration = 0.42
        bounce.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        levelBubble.layer.add(bounce, forKey: "levelTitleBounce")
    }

    private func persistCurrentLevel() {
        guard config.levels.indices.contains(selectedIndex) else { return }
        let level = config.levels[selectedIndex]
        let value = level.value ?? level.title
        if onboardingStepId == "daily_goal" {
            coordinator?.updateDailyGoal(value)
        } else {
            coordinator?.updateSliderLevel(value)
        }
    }

    private func explodeForSliderDetent(_ index: Int) {
        guard let point = slider.knobCenterInWindow() else { return }
        ExplosionManager.trigger(Self.explosionPreset(forDetent: index, count: config.levels.count), at: point)
    }

    /// First detent is tiny; later detents step up through tiny → small → medium.
    private static func explosionPreset(forDetent index: Int, count: Int) -> ExplosionPreset {
        let presets: [ExplosionPreset] = [.tiny, .tiny, .small, .medium]
        guard count > 1 else { return presets[0] }
        let t = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        let mapped = Int((t * Double(presets.count - 1)).rounded())
        return presets[min(max(mapped, 0), presets.count - 1)]
    }
}
