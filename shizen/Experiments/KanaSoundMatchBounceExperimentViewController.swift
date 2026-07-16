//
//  KanaSoundMatchBounceExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: tune the kana match success bounce with live sliders.
//

import UIKit

// MARK: - Tuning sheet

private enum BounceTuningSliderSpec {
    case speed
    case jumpHeight
    case windUp
    case extraBounce

    var title: String {
        switch self {
        case .speed: return "Speed"
        case .jumpHeight: return "Jump height"
        case .windUp: return "Wind-up"
        case .extraBounce: return "Extra bounce"
        }
    }

    var subtitle: String {
        switch self {
        case .speed: return "How fast the whole animation finishes"
        case .jumpHeight: return "How high the card pops up"
        case .windUp: return "Small dip before the jump"
        case .extraBounce: return "Follow-up hops after landing"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .speed: return 0.20 ... 1.20
        case .jumpHeight: return 8 ... 40
        case .windUp: return 0 ... 20
        case .extraBounce: return 0 ... 0.60
        }
    }

    var step: Float {
        switch self {
        case .speed, .extraBounce: return 0.01
        case .jumpHeight, .windUp: return 1
        }
    }

    var unit: String {
        switch self {
        case .speed: return "s"
        case .jumpHeight, .windUp: return "pt"
        case .extraBounce: return ""
        }
    }
}

private struct BounceTuningSliderBinding {
    let spec: BounceTuningSliderSpec
    let read: (KanaSoundMatchBounceConfiguration) -> Float
    let write: (inout KanaSoundMatchBounceConfiguration, Float) -> Void
}

private enum BounceTuningSliderCatalog {
    /// Keeps the tiny second hop proportional when the main follow-up bounce changes.
    private static let secondBounceScale: CGFloat = 0.10 / 0.32

    static let bindings: [BounceTuningSliderBinding] = [
        BounceTuningSliderBinding(spec: .speed, read: { Float($0.duration) }, write: { $0.duration = TimeInterval($1) }),
        BounceTuningSliderBinding(spec: .jumpHeight, read: { Float($0.height) }, write: { $0.height = CGFloat($1) }),
        BounceTuningSliderBinding(
            spec: .windUp,
            read: { Float($0.anticipationDrop) },
            write: { $0.anticipationDrop = CGFloat($1) }
        ),
        BounceTuningSliderBinding(
            spec: .extraBounce,
            read: { Float($0.firstReboundRatio) },
            write: { config, value in
                config.firstReboundRatio = CGFloat(value)
                config.secondReboundRatio = CGFloat(value) * secondBounceScale
            }
        ),
    ]
}

private final class KanaSoundMatchBounceTuningSheetViewController: UIViewController {

    var onChange: ((KanaSoundMatchBounceConfiguration) -> Void)?
    var onReset: (() -> Void)?
    var onPlay: (() -> Void)?

    private var configuration: KanaSoundMatchBounceConfiguration

    private let scrollView = UIScrollView()
    private let sliderStack = UIStackView()
    private let introLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)

    private var sliderRows: [(binding: BounceTuningSliderBinding, slider: UISlider, valueLabel: UILabel)] = []

    init(configuration: KanaSoundMatchBounceConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag

        sliderStack.translatesAutoresizingMaskIntoConstraints = false
        sliderStack.axis = .vertical
        sliderStack.spacing = 18

        introLabel.translatesAutoresizingMaskIntoConstraints = false
        introLabel.font = .preferredFont(forTextStyle: .subheadline)
        introLabel.textColor = .secondaryLabel
        introLabel.numberOfLines = 0
        introLabel.text = "Slide to adjust the success bounce. Tap Play to preview."
        sliderStack.addArrangedSubview(introLabel)

        for binding in BounceTuningSliderCatalog.bindings {
            let row = makeSliderRow(for: binding.spec)
            sliderRows.append((binding, row.slider, row.valueLabel))
            sliderStack.addArrangedSubview(row.container)
        }

        playButton.configuration = .filled()
        playButton.configuration?.title = "Play"
        playButton.addAction(UIAction { [weak self] _ in
            self?.onPlay?()
        }, for: .touchUpInside)

        resetButton.configuration = .gray()
        resetButton.configuration?.title = "Reset"
        resetButton.addAction(UIAction { [weak self] _ in
            self?.onReset?()
        }, for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [playButton, resetButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        sliderStack.addArrangedSubview(buttonRow)

        view.addSubview(scrollView)
        scrollView.addSubview(sliderStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sliderStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            sliderStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            sliderStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            sliderStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            sliderStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        syncSlidersFromConfiguration()
    }

    func sync(configuration: KanaSoundMatchBounceConfiguration) {
        self.configuration = configuration
        syncSlidersFromConfiguration()
    }

    private func makeSliderRow(for spec: BounceTuningSliderSpec) -> (container: UIView, slider: UISlider, valueLabel: UILabel) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label
        titleLabel.text = spec.title

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = spec.subtitle

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = spec.range.lowerBound
        slider.maximumValue = spec.range.upperBound
        slider.addAction(UIAction { [weak self] action in
            guard let self, let slider = action.sender as? UISlider else { return }
            let stepped = Self.steppedValue(slider.value, step: spec.step, range: spec.range)
            slider.value = stepped
            self.handleSliderChange(spec: spec, value: stepped)
        }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in
            self?.onPlay?()
        }, for: .touchUpInside)

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(valueLabel)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            slider.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return (container, slider, valueLabel)
    }

    private static func steppedValue(_ value: Float, step: Float, range: ClosedRange<Float>) -> Float {
        let stepped = (value / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private func handleSliderChange(spec: BounceTuningSliderSpec, value: Float) {
        if let index = sliderRows.firstIndex(where: { $0.binding.spec == spec }) {
            sliderRows[index].binding.write(&configuration, value)
            updateSliderLabel(at: index)
        }
        onChange?(configuration)
    }

    private func syncSlidersFromConfiguration() {
        for (index, row) in sliderRows.enumerated() {
            row.slider.value = row.binding.read(configuration)
            updateSliderLabel(at: index)
        }
    }

    private func updateSliderLabel(at index: Int) {
        let row = sliderRows[index]
        row.valueLabel.text = formattedValue(row.binding.read(configuration), spec: row.binding.spec)
    }

    private func formattedValue(_ value: Float, spec: BounceTuningSliderSpec) -> String {
        switch spec {
        case .speed:
            return String(format: "%.2f %@", value, spec.unit)
        case .jumpHeight, .windUp:
            return String(format: "%.0f %@", value, spec.unit)
        case .extraBounce:
            return value < 0.05 ? "None" : String(format: "%.0f%%", value * 100)
        }
    }
}

// MARK: - Experiment

final class KanaSoundMatchBounceExperimentViewController: UIViewController {

    private var configuration = KanaSoundMatchBounceConfiguration.production
    private let previewCardRotationDegrees: Float = 3

    private let previewContainer = UIView()
    private let soundPanel = UIView()
    private let choiceLabel = UILabel()
    private let previewCard = UIView()
    private let previewLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    private weak var tuningSheet: KanaSoundMatchBounceTuningSheetViewController?
    private var didPresentTuningSheet = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Match bounce"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Tune",
            primaryAction: UIAction { [weak self] _ in
                self?.presentTuningSheet(animated: true)
            }
        )

        configurePreview()
        layoutViews()
        applyPreviewTransform()

        view.clipsToBounds = false
        previewContainer.clipsToBounds = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentTuningSheet else { return }
        didPresentTuningSheet = true
        presentTuningSheet(animated: animated)
        replayBounce()
    }

    private func configurePreview() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        soundPanel.translatesAutoresizingMaskIntoConstraints = false
        soundPanel.backgroundColor = ExperimentPalette.successFill
        soundPanel.layer.cornerRadius = 12
        soundPanel.layer.cornerCurve = .continuous
        soundPanel.layer.borderWidth = 3
        soundPanel.layer.borderColor = ExperimentPalette.successBorder.cgColor

        choiceLabel.translatesAutoresizingMaskIntoConstraints = false
        choiceLabel.text = "ka"
        choiceLabel.font = .systemFont(ofSize: 24, weight: .medium)
        choiceLabel.textAlignment = .center
        choiceLabel.textColor = .label

        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.backgroundColor = ExperimentPalette.dragCardSurface
        previewCard.layer.cornerRadius = 14
        previewCard.layer.cornerCurve = .continuous
        previewCard.layer.borderWidth = 1
        previewCard.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        previewCard.isUserInteractionEnabled = true
        previewCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePreviewTap)))

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.text = "か"
        previewLabel.font = .systemFont(ofSize: 30, weight: .bold)
        previewLabel.textAlignment = .center
        previewLabel.textColor = .label
        previewLabel.isUserInteractionEnabled = false

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.configuration = .filled()
        playButton.configuration?.title = "Play bounce"
        playButton.addAction(UIAction { [weak self] _ in
            self?.replayBounce()
        }, for: .touchUpInside)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "Tap the card or release a slider to preview"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        previewContainer.addSubview(soundPanel)
        soundPanel.addSubview(choiceLabel)
        previewContainer.addSubview(previewCard)
        previewCard.addSubview(previewLabel)
    }

    private func layoutViews() {
        view.addSubview(previewContainer)
        view.addSubview(playButton)
        view.addSubview(hintLabel)

        let cardSide = KanaSoundMatchMetrics.kanaCardSide
        let panelHeight: CGFloat = 96

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            previewContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            previewContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            previewContainer.widthAnchor.constraint(equalToConstant: 160),
            previewContainer.heightAnchor.constraint(equalToConstant: 180),

            soundPanel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            soundPanel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor, constant: 12),
            soundPanel.widthAnchor.constraint(equalToConstant: 120),
            soundPanel.heightAnchor.constraint(equalToConstant: panelHeight),

            choiceLabel.centerXAnchor.constraint(equalTo: soundPanel.centerXAnchor),
            choiceLabel.centerYAnchor.constraint(equalTo: soundPanel.centerYAnchor, constant: 12),

            previewCard.centerXAnchor.constraint(equalTo: soundPanel.centerXAnchor),
            previewCard.centerYAnchor.constraint(equalTo: soundPanel.topAnchor, constant: 12),
            previewCard.widthAnchor.constraint(equalToConstant: cardSide),
            previewCard.heightAnchor.constraint(equalToConstant: cardSide),

            previewLabel.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            previewLabel.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),

            playButton.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 28),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),

            hintLabel.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func presentTuningSheet(animated: Bool) {
        if let tuningSheet, tuningSheet.presentingViewController != nil {
            return
        }

        let sheet = KanaSoundMatchBounceTuningSheetViewController(configuration: configuration)
        sheet.onChange = { [weak self] configuration in
            self?.applyTuning(configuration: configuration)
        }
        sheet.onReset = { [weak self] in
            self?.resetToProduction()
        }
        sheet.onPlay = { [weak self] in
            self?.replayBounce()
        }
        tuningSheet = sheet

        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium()]
            presentation.largestUndimmedDetentIdentifier = .medium
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(sheet, animated: animated)
    }

    private func applyTuning(configuration: KanaSoundMatchBounceConfiguration) {
        self.configuration = configuration
        applyPreviewTransform()
    }

    private func previewTransform() -> CGAffineTransform {
        let radians = CGFloat(previewCardRotationDegrees) * .pi / 180
        return CGAffineTransform(rotationAngle: radians)
    }

    private func applyPreviewTransform() {
        previewCard.transform = previewTransform()
    }

    @objc private func handlePreviewTap() {
        replayBounce()
    }

    private func replayBounce() {
        applyPreviewTransform()
        previewCard.animateKanaSoundMatchBounce(
            configuration: configuration,
            baseTransform: previewTransform()
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func resetToProduction() {
        configuration = .production
        tuningSheet?.sync(configuration: configuration)
        applyPreviewTransform()
        replayBounce()
    }
}
