import InteractionKit
import UIKit

/// Live tuner for the multi-word selection pill. Values are saved and used
/// by every sentence scrub.
final class MultiSelectHighlightExperimentViewController: UIViewController {

    private let sampleSentence = "昨日は友達と映画を見に行きました。"

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let scrub = ScrubbableSentenceView(engine: JapaneseScrubSentenceEngine.shared)
    private let previewCard = UIView()

    private let fillSwatchRow = UIStackView()
    private let bandSwatchRow = UIStackView()
    private var fillButtons: [UIButton] = []
    private var bandButtons: [UIButton] = []

    private let heightSlider = UISlider()
    private let heightValueLabel = UILabel()
    private let radiusSlider = UISlider()
    private let radiusValueLabel = UILabel()
    private let textColorControl = UISegmentedControl(items: ["White", "Dark"])

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Multi-select highlight"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset",
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )

        configureLayout()
        reloadControls()
        ExperimentSettings.applySpanHighlightStyle()

        scrub.onTokensApplied = { [weak self] count in
            self?.showSampleSpan(tokenCount: count)
        }
        scrub.showCalloutOnScrub = false
        scrub.configure(
            sentence: sampleSentence,
            font: .systemFont(ofSize: 28, weight: .semibold),
            showsFurigana: true
        )
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 22
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 32, right: 20)
        scrollView.addSubview(contentStack)

        configurePreviewCard()

        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(makeSection(
            title: "Background",
            detail: "The pill behind the selected words.",
            body: fillSwatchRow
        ))
        contentStack.addArrangedSubview(makeSection(
            title: "Secondary highlight",
            detail: "The darker band along the bottom of the pill.",
            body: bandSwatchRow
        ))
        contentStack.addArrangedSubview(makeSliderSection(
            title: "Band height",
            slider: heightSlider,
            valueLabel: heightValueLabel,
            min: 0.15,
            max: 1,
            action: #selector(heightChanged)
        ))
        contentStack.addArrangedSubview(makeSliderSection(
            title: "Corner radius",
            slider: radiusSlider,
            valueLabel: radiusValueLabel,
            min: 0,
            max: 14,
            action: #selector(radiusChanged)
        ))
        contentStack.addArrangedSubview(makeTextColorSection())

        fillSwatchRow.axis = .horizontal
        fillSwatchRow.spacing = 10
        bandSwatchRow.axis = .horizontal
        bandSwatchRow.spacing = 10

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        rebuildSwatches()
    }

    private func configurePreviewCard() {
        previewCard.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55)
        previewCard.layer.cornerRadius = 22
        previewCard.layer.cornerCurve = .continuous

        let caption = UILabel()
        caption.font = .preferredFont(forTextStyle: .caption1)
        caption.textColor = .tertiaryLabel
        caption.textAlignment = .center
        caption.numberOfLines = 0
        caption.text = "Sample span. Long-press the sentence to drag your own."

        let restore = UIButton(type: .system)
        restore.setTitle("Show sample span", for: .normal)
        restore.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        restore.addTarget(self, action: #selector(restoreSampleSpan), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [caption, scrub, restore])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        previewCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: previewCard.topAnchor),
            stack.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor),
        ])
    }

    private func makeSection(title: String, detail: String, body: UIView) -> UIView {
        let header = sectionTitle(title)
        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = true
        body.translatesAutoresizingMaskIntoConstraints = false
        if let row = body as? UIStackView {
            row.alignment = .center
        }
        scroller.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            body.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            scroller.heightAnchor.constraint(equalToConstant: 44),
        ])

        let stack = UIStackView(arrangedSubviews: [header, detailLabel, scroller])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeSliderSection(
        title: String,
        slider: UISlider,
        valueLabel: UILabel,
        min: Float,
        max: Float,
        action: Selector
    ) -> UIView {
        let header = sectionTitle(title)
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        slider.minimumValue = min
        slider.maximumValue = max
        slider.addTarget(self, action: action, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [slider, valueLabel])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, row])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeTextColorSection() -> UIView {
        let header = sectionTitle("Text")
        let detail = UILabel()
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.text = "Use dark text when the fill is light."
        textColorControl.addTarget(self, action: #selector(textColorChanged), for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [header, detail, textColorControl])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = text
        return label
    }

    private func rebuildSwatches() {
        fillButtons.forEach { $0.removeFromSuperview() }
        bandButtons.forEach { $0.removeFromSuperview() }
        fillButtons = DialogueBubbleUnderglowColor.allCases.map { color in
            let button = swatchButton(color: color, action: #selector(fillColorTapped(_:)))
            fillSwatchRow.addArrangedSubview(button)
            return button
        }
        bandButtons = DialogueBubbleUnderglowColor.allCases.map { color in
            let button = swatchButton(color: color, action: #selector(bandColorTapped(_:)))
            bandSwatchRow.addArrangedSubview(button)
            return button
        }
        refreshSwatchSelection()
    }

    private func swatchButton(color: DialogueBubbleUnderglowColor, action: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = color.rawValue
        button.accessibilityLabel = color.title
        button.backgroundColor = color.uiColor
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        return button
    }

    private func reloadControls() {
        heightSlider.value = Float(ExperimentSettings.spanHighlightBandHeight)
        radiusSlider.value = Float(ExperimentSettings.spanHighlightCornerRadius)
        textColorControl.selectedSegmentIndex = ExperimentSettings.spanHighlightUsesDarkText ? 1 : 0
        updateSliderLabels()
        refreshSwatchSelection()
    }

    private func updateSliderLabels() {
        heightValueLabel.text = "\(Int((heightSlider.value * 100).rounded()))%"
        radiusValueLabel.text = "\(Int(radiusSlider.value.rounded())) pt"
    }

    private func refreshSwatchSelection() {
        mark(fillButtons, selected: ExperimentSettings.spanHighlightFillColor)
        mark(bandButtons, selected: ExperimentSettings.spanHighlightBandColor)
    }

    private func mark(_ buttons: [UIButton], selected: DialogueBubbleUnderglowColor) {
        for button in buttons {
            let isSelected = button.tag == selected.rawValue
            button.layer.borderWidth = isSelected ? 3 : 0
            button.layer.borderColor = UIColor.label.cgColor
            button.transform = isSelected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }

    private func showSampleSpan(tokenCount: Int) {
        guard tokenCount > 1 else { return }
        let upper = min(6, tokenCount - 1)
        let lower = min(2, upper)
        scrub.showSpanHighlight(lower...upper)
    }

    @objc private func restoreSampleSpan() {
        showSampleSpan(tokenCount: scrub.tokenCount)
    }

    @objc private func fillColorTapped(_ sender: UIButton) {
        guard let color = DialogueBubbleUnderglowColor(rawValue: sender.tag) else { return }
        ExperimentSettings.spanHighlightFillColor = color
        publish()
    }

    @objc private func bandColorTapped(_ sender: UIButton) {
        guard let color = DialogueBubbleUnderglowColor(rawValue: sender.tag) else { return }
        ExperimentSettings.spanHighlightBandColor = color
        publish()
    }

    @objc private func heightChanged() {
        ExperimentSettings.spanHighlightBandHeight = CGFloat(heightSlider.value)
        updateSliderLabels()
        publish()
    }

    @objc private func radiusChanged() {
        ExperimentSettings.spanHighlightCornerRadius = CGFloat(radiusSlider.value)
        updateSliderLabels()
        publish()
    }

    @objc private func textColorChanged() {
        ExperimentSettings.spanHighlightUsesDarkText = textColorControl.selectedSegmentIndex == 1
        publish()
    }

    @objc private func resetTapped() {
        ExperimentSettings.resetSpanHighlightStyle()
        reloadControls()
    }

    private func publish() {
        ExperimentSettings.applySpanHighlightStyle()
        refreshSwatchSelection()
    }
}
