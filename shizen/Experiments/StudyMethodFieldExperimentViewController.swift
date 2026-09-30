//
//  StudyMethodFieldExperimentViewController.swift
//  shizen
//
//  DEBUG: live tuner for the floating study-method pills.
//

import UIKit

final class StudyMethodFieldExperimentViewController: UIViewController {

    private static let titleEdgeFeather: CGFloat = 72

    private let closeButton = OnboardingChrome.makeCircularIconButton(symbolName: "xmark")
    private let tuneButton = OnboardingChrome.makeCircularIconButton(symbolName: "slider.horizontal.3")
    private let titleContainer = UIView()
    private let titleEdgeMask = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let field = StudyMethodFloatField()
    private let replayButton = PrimaryButton(type: .system)
    private let dropButton = PrimaryButton(type: .system)
    private var didPresentSheet = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        configureField()
        configureHeader()
        configureDrop()
        view.sendSubviewToBack(field)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.resumeFloatingIfNeeded()
        guard !didPresentSheet else { return }
        didPresentSheet = true
        presentTuningSheet(animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        field.stopFloating()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = titleContainer.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        titleEdgeMask.frame = bounds
        let feather = min(Self.titleEdgeFeather, bounds.height * 0.45)
        let solid = (bounds.height - feather) / bounds.height
        titleEdgeMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
        ]
        titleEdgeMask.locations = [0, NSNumber(value: Double(solid)), 1]
    }

    private func configureField() {
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.topAnchor),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            field.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureHeader() {
        titleContainer.backgroundColor = ExperimentPalette.pageBackground
        titleContainer.isUserInteractionEnabled = false
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleEdgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        titleEdgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        titleContainer.layer.mask = titleEdgeMask
        view.addSubview(titleContainer)

        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        tuneButton.accessibilityLabel = "Tune"
        tuneButton.addTarget(self, action: #selector(tuneTapped), for: .touchUpInside)
        view.addSubview(tuneButton)

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = "Learning Japanese got\ncomplicated."
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = OnboardingChrome.subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "Lists, decks, apps; when did it get\nso complicated?"
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleContainer.topAnchor.constraint(equalTo: view.topAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleContainer.bottomAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16 + Self.titleEdgeFeather),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tuneButton.topAnchor.constraint(equalTo: closeButton.topAnchor),
            tuneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: OnboardingChrome.titleHorizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -OnboardingChrome.titleHorizontalInset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    private func configureDrop() {
        replayButton.primaryStyle = .yellow
        replayButton.setTitle("Replay", for: .normal)
        replayButton.addTarget(self, action: #selector(replayTapped), for: .touchUpInside)

        dropButton.primaryStyle = .yellow
        dropButton.setTitle("Drop", for: .normal)
        dropButton.addTarget(self, action: #selector(dropTapped), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [replayButton, dropButton])
        actions.axis = .horizontal
        actions.spacing = 12
        actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            replayButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            dropButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    private func presentTuningSheet(animated: Bool) {
        guard presentedViewController == nil else { return }
        let sheet = StudyMethodFieldTuningSheetViewController(tuning: field.tuning)
        sheet.onChange = { [weak self] tuning in
            self?.field.apply(tuning)
        }
        sheet.onReplay = { [weak self] in
            self?.field.startFloating()
        }
        sheet.onDrop = { [weak self] in
            self?.dropTapped()
        }
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .medium
            presentation.largestUndimmedDetentIdentifier = .medium
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = false
            presentation.preferredCornerRadius = 28
        }
        present(sheet, animated: animated)
    }

    @objc private func tuneTapped() {
        presentTuningSheet(animated: true)
    }

    @objc private func replayTapped() {
        field.startFloating()
    }

    @objc private func dropTapped() {
        field.dropUnderGravity { [weak self] in
            self?.field.startFloating()
        }
    }

    @objc private func closeTapped() {
        if presentingViewController != nil {
            presentingViewController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}

private final class StudyMethodFieldTuningSheetViewController: UIViewController {

    var onChange: ((StudyMethodFieldTuning) -> Void)?
    var onReplay: (() -> Void)?
    var onDrop: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let copyButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let replayButton = PrimaryButton(type: .system)
    private let dropButton = PrimaryButton(type: .system)

    private let sizeSlider = UISlider()
    private let depthSlider = UISlider()
    private let blurSlider = UISlider()
    private let hapticSlider = UISlider()
    private let flowSlider = UISlider()
    private let gravitySlider = UISlider()
    private let staggerSlider = UISlider()
    private let rotationSlider = UISlider()
    private let countSlider = UISlider()
    private let glowSlider = UISlider()
    private let dropCutoffSlider = UISlider()
    private let popGapSlider = UISlider()
    private let popRampSlider = UISlider()
    private let popSpringSlider = UISlider()
    private let popDampingSlider = UISlider()
    private let popFromSlider = UISlider()
    private let popCenterSlider = UISlider()
    private let singleHapticSwitch = UISwitch()
    private let reverseFlowSwitch = UISwitch()
    private var applied: StudyMethodFieldTuning

    init(tuning: StudyMethodFieldTuning) {
        applied = tuning
        super.init(nibName: nil, bundle: nil)
        sizeSlider.value = Float(tuning.size)
        depthSlider.value = Float(tuning.depth)
        blurSlider.value = Float(tuning.blur)
        hapticSlider.value = tuning.hapticStrength
        flowSlider.value = Float(tuning.flowSpeed)
        gravitySlider.value = Float(tuning.gravity)
        staggerSlider.value = Float(tuning.gravityStagger)
        rotationSlider.value = Float(tuning.rotation)
        countSlider.value = Float(tuning.count)
        glowSlider.value = Float(tuning.glow)
        dropCutoffSlider.value = Float(tuning.dropCutoff)
        popGapSlider.value = Float(tuning.popGap)
        popRampSlider.value = Float(tuning.popRamp)
        popSpringSlider.value = Float(tuning.popSpring)
        popDampingSlider.value = Float(tuning.popDamping)
        popFromSlider.value = Float(tuning.popFrom)
        popCenterSlider.value = Float(tuning.popCenterCount)
        singleHapticSwitch.isOn = tuning.singleHaptic
        reverseFlowSwitch.isOn = tuning.flowReversed
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.cardSurface
        configureControls()
    }

    private func configureControls() {
        replayButton.primaryStyle = .yellow
        replayButton.setTitle("Replay", for: .normal)
        replayButton.addTarget(self, action: #selector(replayTapped), for: .touchUpInside)

        dropButton.primaryStyle = .yellow
        dropButton.setTitle("Drop", for: .normal)
        dropButton.addTarget(self, action: #selector(dropTapped), for: .touchUpInside)

        copyButton.setTitle("Copy values", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        resetButton.setTitle("Reset", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [replayButton, dropButton])
        actions.axis = .horizontal
        actions.spacing = 12
        actions.distribution = .fillEqually

        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        let utilities = UIStackView(arrangedSubviews: [copyButton, resetButton])
        utilities.axis = .horizontal
        utilities.spacing = 16
        utilities.alignment = .center

        let buttons = UIStackView(arrangedSubviews: [actions, utilities])
        buttons.axis = .vertical
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        configureSlider(sizeSlider, min: 0.7, max: 1.45, value: Float(applied.size), structural: false)
        configureSlider(depthSlider, min: 0, max: 1.6, value: Float(applied.depth), structural: true)
        configureSlider(blurSlider, min: 0, max: 22, value: Float(applied.blur), structural: true)
        configureSlider(hapticSlider, min: 0, max: 1, value: applied.hapticStrength, structural: false)
        configureSlider(flowSlider, min: 0.01, max: 0.1, value: Float(applied.flowSpeed), structural: false)
        configureSlider(gravitySlider, min: 2, max: 16, value: Float(applied.gravity), structural: false)
        configureSlider(staggerSlider, min: 0, max: 1.2, value: Float(applied.gravityStagger), structural: false)
        configureSlider(rotationSlider, min: 0, max: 12, value: Float(applied.rotation), structural: false)
        configureSlider(countSlider, min: 16, max: 120, value: Float(applied.count), structural: true)
        configureSlider(glowSlider, min: 0, max: 1.6, value: Float(applied.glow), structural: false)
        configureSlider(dropCutoffSlider, min: 0, max: 1, value: Float(applied.dropCutoff), structural: false)
        configureSlider(popGapSlider, min: 0.04, max: 0.45, value: Float(applied.popGap), structural: false, replaysEntrance: true)
        configureSlider(popRampSlider, min: 1, max: 10, value: Float(applied.popRamp), structural: false, replaysEntrance: true)
        configureSlider(popSpringSlider, min: 6, max: 32, value: Float(applied.popSpring), structural: false, replaysEntrance: true)
        configureSlider(popDampingSlider, min: 0.35, max: 1, value: Float(applied.popDamping), structural: false, replaysEntrance: true)
        configureSlider(popFromSlider, min: 0.05, max: 0.85, value: Float(applied.popFrom), structural: false, replaysEntrance: true)
        configureSlider(popCenterSlider, min: 0, max: 48, value: Float(applied.popCenterCount), structural: false, replaysEntrance: true)

        stack.addArrangedSubview(sectionLabel("Entrance"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Appear gap", slider: popGapSlider, format: "%.2f s"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Appear ramp", slider: popRampSlider, format: "%.1f×"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Spring", slider: popSpringSlider, format: "%.1f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Damping", slider: popDampingSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Start scale", slider: popFromSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Center first", slider: popCenterSlider, format: "%.0f"))
        stack.addArrangedSubview(sectionLabel("Field"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Size", slider: sizeSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Depth", slider: depthSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Blur", slider: blurSlider, format: "%.1f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Haptic", slider: hapticSlider, format: "%.2f"))
        stack.addArrangedSubview(switchRow(title: "Single haptic", toggle: singleHapticSwitch))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Flow", slider: flowSlider, format: "%.3f"))
        stack.addArrangedSubview(switchRow(title: "Reverse flow", toggle: reverseFlowSwitch))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Gravity", slider: gravitySlider, format: "%.1f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Stagger", slider: staggerSlider, format: "%.2f s"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Rotation", slider: rotationSlider, format: "%.1f°"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Count", slider: countSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Glow", slider: glowSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Drop cutoff", slider: dropCutoffSlider, format: "%.2f"))

        view.addSubview(buttons)
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            buttons.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            replayButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            dropButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            scrollView.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func switchRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        toggle.onTintColor = .systemYellow
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    @objc private func toggleChanged() {
        onChange?(reading(holdingStructural: true))
    }

    private func sectionLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        return label
    }

    private func configureSlider(
        _ slider: UISlider,
        min: Float,
        max: Float,
        value: Float,
        structural: Bool,
        replaysEntrance: Bool = false
    ) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.minimumTrackTintColor = .systemYellow
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        if structural {
            slider.addTarget(self, action: #selector(sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        } else if replaysEntrance {
            slider.addTarget(self, action: #selector(entranceSliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
    }

    private var structuralSliders: [UISlider] {
        [depthSlider, blurSlider, countSlider]
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        guard !structuralSliders.contains(where: { $0 === sender }) else { return }
        onChange?(reading(holdingStructural: true))
    }

    @objc private func sliderEnded() {
        let tuning = reading(holdingStructural: false)
        applied = tuning
        onChange?(tuning)
    }

    @objc private func entranceSliderEnded() {
        onChange?(reading(holdingStructural: true))
        onReplay?()
    }

    private func reading(holdingStructural: Bool) -> StudyMethodFieldTuning {
        StudyMethodFieldTuning(
            size: CGFloat(sizeSlider.value),
            depth: holdingStructural ? applied.depth : CGFloat(depthSlider.value),
            blur: holdingStructural ? applied.blur : CGFloat(blurSlider.value),
            hapticStrength: hapticSlider.value,
            flowSpeed: CGFloat(flowSlider.value),
            gravity: CGFloat(gravitySlider.value),
            gravityStagger: CGFloat(staggerSlider.value),
            rotation: CGFloat(rotationSlider.value),
            count: holdingStructural ? applied.count : Int(countSlider.value.rounded()),
            glow: CGFloat(glowSlider.value),
            dropCutoff: CGFloat(dropCutoffSlider.value),
            singleHaptic: singleHapticSwitch.isOn,
            flowReversed: reverseFlowSwitch.isOn,
            popGap: CGFloat(popGapSlider.value),
            popRamp: CGFloat(popRampSlider.value),
            popSpring: CGFloat(popSpringSlider.value),
            popDamping: CGFloat(popDampingSlider.value),
            popFrom: CGFloat(popFromSlider.value),
            popCenterCount: Int(popCenterSlider.value.rounded())
        )
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = reading(holdingStructural: false).sourceText
        copyButton.setTitle("Copied", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle("Copy values", for: .normal)
        }
    }

    @objc private func replayTapped() {
        onChange?(reading(holdingStructural: true))
        onReplay?()
    }

    @objc private func dropTapped() {
        onDrop?()
    }

    @objc private func resetTapped() {
        let tuning = StudyMethodFieldTuning()
        sizeSlider.value = Float(tuning.size)
        depthSlider.value = Float(tuning.depth)
        blurSlider.value = Float(tuning.blur)
        hapticSlider.value = tuning.hapticStrength
        flowSlider.value = Float(tuning.flowSpeed)
        gravitySlider.value = Float(tuning.gravity)
        staggerSlider.value = Float(tuning.gravityStagger)
        rotationSlider.value = Float(tuning.rotation)
        countSlider.value = Float(tuning.count)
        glowSlider.value = Float(tuning.glow)
        dropCutoffSlider.value = Float(tuning.dropCutoff)
        popGapSlider.value = Float(tuning.popGap)
        popRampSlider.value = Float(tuning.popRamp)
        popSpringSlider.value = Float(tuning.popSpring)
        popDampingSlider.value = Float(tuning.popDamping)
        popFromSlider.value = Float(tuning.popFrom)
        popCenterSlider.value = Float(tuning.popCenterCount)
        singleHapticSwitch.isOn = tuning.singleHaptic
        reverseFlowSwitch.isOn = tuning.flowReversed
        applied = tuning
        for slider in [sizeSlider, depthSlider, blurSlider, hapticSlider, flowSlider, gravitySlider, staggerSlider, rotationSlider, countSlider, glowSlider, dropCutoffSlider, popGapSlider, popRampSlider, popSpringSlider, popDampingSlider, popFromSlider, popCenterSlider] {
            slider.sendActions(for: .valueChanged)
        }
        onChange?(tuning)
        onReplay?()
    }
}
