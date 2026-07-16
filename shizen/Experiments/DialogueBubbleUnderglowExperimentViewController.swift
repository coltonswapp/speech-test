//
//  DialogueBubbleUnderglowExperimentViewController.swift
//  shizen
//
//  DEBUG: single glass dialogue bubble with live underglow tuning controls.
//

import UIKit

final class DialogueBubbleUnderglowExperimentViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let previewContainer = UIView()
    private let introLabel = UILabel()
    private let configLabel = UILabel()
    private let edgeSelector = UISegmentedControl(items: DialogueBubbleUnderglowVerticalEdge.allCases.map(\.title))
    private let colorSelector = UISegmentedControl(items: DialogueBubbleUnderglowColor.allCases.map(\.title))
    private let emphasisSlider = UISlider()
    private let heightRatioSlider = UISlider()
    private let widthRatioSlider = UISlider()
    private let horizontalInsetSlider = UISlider()
    private let offsetXSlider = UISlider()
    private let offsetYSlider = UISlider()
    private let opacitySlider = UISlider()
    private let cornerRadiusSlider = UISlider()
    private let blurRadiusSlider = UISlider()
    private let resetButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)

    private var bubble: DialogueJapaneseBubbleView!
    private var configuration = DialogueBubbleUnderglowConfiguration.default

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bubble underglow"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        configurePreview()
        configureControls()
        applyConfigurationToBubble()
    }

    private func configurePreview() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.35)
        previewContainer.layer.cornerRadius = 24
        previewContainer.layer.cornerCurve = .continuous

        let font = UIFont.systemFont(ofSize: 22, weight: .medium)
        var displayInsets = JapaneseFuriganaBuilder.compactDisplayInsets(for: font)
        displayInsets.top += 6

        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .natural
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: label,
            attributed: JapaneseFuriganaBuilder.scenarioAttributedString(
                for: "今日はいい天気ですね。",
                font: font,
                textColor: .label
            ),
            contentInsets: displayInsets
        )

        bubble = DialogueJapaneseBubbleView(label: label)
        bubble.setBackgroundStyle(.glass)
        bubble.setEmphasis(1)

        previewContainer.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            bubble.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: previewContainer.leadingAnchor, constant: 24),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: previewContainer.trailingAnchor, constant: -24),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
    }

    private func configureControls() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        introLabel.font = .preferredFont(forTextStyle: .subheadline)
        introLabel.textColor = .secondaryLabel
        introLabel.numberOfLines = 0
        introLabel.textAlignment = .center
        introLabel.text = "Tune the underglow behind the glass bubble. Values update live below."

        configLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        configLabel.textColor = .tertiaryLabel
        configLabel.numberOfLines = 0
        configLabel.textAlignment = .left

        edgeSelector.selectedSegmentIndex = configuration.verticalEdge.rawValue
        edgeSelector.addTarget(self, action: #selector(edgeChanged), for: .valueChanged)

        colorSelector.selectedSegmentIndex = configuration.color.rawValue
        colorSelector.addTarget(self, action: #selector(colorChanged), for: .valueChanged)

        configureSlider(emphasisSlider, min: 0, max: 1, value: 1, action: #selector(sliderChanged))
        configureSlider(heightRatioSlider, min: 0.05, max: 1, value: Float(configuration.heightRatio), action: #selector(sliderChanged))
        configureSlider(widthRatioSlider, min: 0.05, max: 1, value: Float(configuration.widthRatio), action: #selector(sliderChanged))
        configureSlider(horizontalInsetSlider, min: 0, max: 48, value: Float(configuration.horizontalInset), action: #selector(sliderChanged))
        configureSlider(offsetXSlider, min: -80, max: 80, value: Float(configuration.offsetX), action: #selector(sliderChanged))
        configureSlider(offsetYSlider, min: -80, max: 80, value: Float(configuration.offsetY), action: #selector(sliderChanged))
        configureSlider(opacitySlider, min: 0, max: 1, value: Float(configuration.opacity), action: #selector(sliderChanged))
        configureSlider(
            cornerRadiusSlider,
            min: 0,
            max: 36,
            value: Float(configuration.cornerRadius),
            action: #selector(sliderChanged)
        )
        configureSlider(
            blurRadiusSlider,
            min: 0,
            max: 40,
            value: Float(configuration.blurRadius),
            action: #selector(sliderChanged)
        )

        resetButton.configuration = .gray()
        resetButton.configuration?.title = "Reset to defaults"
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        copyButton.configuration = .tinted()
        copyButton.configuration?.title = "Copy values"
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        let controlsStack = UIStackView(arrangedSubviews: [
            introLabel,
            previewContainer,
            edgeSelector,
            colorSelector,
            ExperimentSliderRow.make(title: "Emphasis", slider: emphasisSlider, format: "%.2f"),
            ExperimentSliderRow.make(title: "Height ratio", slider: heightRatioSlider, format: "%.2f"),
            ExperimentSliderRow.make(title: "Width ratio", slider: widthRatioSlider, format: "%.2f"),
            ExperimentSliderRow.make(title: "Horizontal inset", slider: horizontalInsetSlider, format: "%.0f pt"),
            ExperimentSliderRow.make(title: "Offset X", slider: offsetXSlider, format: "%.2f pt"),
            ExperimentSliderRow.make(title: "Offset Y", slider: offsetYSlider, format: "%.2f pt"),
            ExperimentSliderRow.make(title: "Glow opacity", slider: opacitySlider, format: "%.2f"),
            ExperimentSliderRow.make(title: "Corner radius", slider: cornerRadiusSlider, format: "%.0f pt"),
            ExperimentSliderRow.make(title: "Blur radius", slider: blurRadiusSlider, format: "%.0f pt"),
            resetButton,
            copyButton,
            configLabel,
        ])
        controlsStack.axis = .vertical
        controlsStack.spacing = 16
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(controlsStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),

            previewContainer.heightAnchor.constraint(equalToConstant: 180),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func edgeChanged() {
        configuration.verticalEdge = DialogueBubbleUnderglowVerticalEdge(rawValue: edgeSelector.selectedSegmentIndex) ?? .bottom
        applyConfigurationToBubble()
    }

    @objc private func colorChanged() {
        configuration.color = DialogueBubbleUnderglowColor(rawValue: colorSelector.selectedSegmentIndex) ?? .yellow
        applyConfigurationToBubble()
    }

    @objc private func sliderChanged() {
        configuration.heightRatio = CGFloat(heightRatioSlider.value)
        configuration.widthRatio = CGFloat(widthRatioSlider.value)
        configuration.horizontalInset = CGFloat(horizontalInsetSlider.value)
        configuration.offsetX = CGFloat(offsetXSlider.value)
        configuration.offsetY = CGFloat(offsetYSlider.value)
        configuration.opacity = CGFloat(opacitySlider.value)
        configuration.cornerRadius = CGFloat(cornerRadiusSlider.value)
        configuration.blurRadius = CGFloat(blurRadiusSlider.value)
        applyConfigurationToBubble()
        bubble.setEmphasis(CGFloat(emphasisSlider.value))
    }

    @objc private func resetTapped() {
        configuration = .default
        edgeSelector.selectedSegmentIndex = configuration.verticalEdge.rawValue
        colorSelector.selectedSegmentIndex = configuration.color.rawValue
        emphasisSlider.value = 1
        heightRatioSlider.value = Float(configuration.heightRatio)
        widthRatioSlider.value = Float(configuration.widthRatio)
        horizontalInsetSlider.value = Float(configuration.horizontalInset)
        offsetXSlider.value = Float(configuration.offsetX)
        offsetYSlider.value = Float(configuration.offsetY)
        opacitySlider.value = Float(configuration.opacity)
        cornerRadiusSlider.value = Float(configuration.cornerRadius)
        blurRadiusSlider.value = Float(configuration.blurRadius)
        applyConfigurationToBubble()
        bubble.setEmphasis(1)
        refreshSliderValueLabels()
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = configuration.debugSummary()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func applyConfigurationToBubble() {
        bubble.setUnderglowConfiguration(configuration)
        configLabel.text = configuration.debugSummary()
    }

    private func configureSlider(_ slider: UISlider, min: Float, max: Float, value: Float, action: Selector) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: action, for: .valueChanged)
    }

    private func refreshSliderValueLabels() {
        for slider in [emphasisSlider, heightRatioSlider, widthRatioSlider, horizontalInsetSlider, offsetXSlider, offsetYSlider, opacitySlider, cornerRadiusSlider, blurRadiusSlider] {
            slider.sendActions(for: .valueChanged)
        }
    }
}
