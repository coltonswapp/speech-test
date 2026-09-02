//
//  DialogueHighlightColorPickerViewController.swift
//  shizen
//
//  Sheet of left/right highlight presets for Dialogue Recording, with a live
//  example of underglow + token karaoke on each side.
//

import UIKit

final class DialogueHighlightColorPickerViewController: UIViewController {

    var onChange: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let previewCard = UIView()
    private let previewStack = UIStackView()
    private var leadingBubble: DialogueJapaneseBubbleView!
    private var trailingBubble: DialogueJapaneseBubbleView!
    private let presetStack = UIStackView()
    private var presetButtons: [UIButton] = []

    private static let leadingSample = "駅はどこですか？"
    private static let trailingSample = "まっすぐ行ってください。"
    private static let leadingHighlight = "どこ"
    private static let trailingHighlight = "まっすぐ"
    private static let sampleFont = UIFont.systemFont(ofSize: 20, weight: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Highlight colors"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        configureLayout()
        rebuildPresetButtons()
        refreshPreview()
        refreshPresetSelection()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 28, right: 20)
        scrollView.addSubview(contentStack)

        let intro = UILabel()
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        intro.text = "Pick a preset for each side’s underglow and spoken-word highlight."

        configurePreviewCard()

        let presetsHeader = UILabel()
        presetsHeader.font = .preferredFont(forTextStyle: .headline)
        presetsHeader.text = "Presets"

        presetStack.axis = .vertical
        presetStack.spacing = 10

        contentStack.addArrangedSubview(intro)
        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(presetsHeader)
        contentStack.addArrangedSubview(presetStack)

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
    }

    private func configurePreviewCard() {
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55)
        previewCard.layer.cornerRadius = 22
        previewCard.layer.cornerCurve = .continuous

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .preferredFont(forTextStyle: .caption1)
        title.textColor = .tertiaryLabel
        title.textAlignment = .center
        title.text = "Example"

        leadingBubble = makeSampleBubble(
            text: Self.leadingSample,
            highlight: Self.leadingHighlight,
            side: .leading
        )
        trailingBubble = makeSampleBubble(
            text: Self.trailingSample,
            highlight: Self.trailingHighlight,
            side: .trailing
        )

        let leadingColumn = makePreviewColumn(
            speaker: "A",
            side: .leading,
            bubble: leadingBubble
        )
        let trailingColumn = makePreviewColumn(
            speaker: "B",
            side: .trailing,
            bubble: trailingBubble
        )

        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewStack.axis = .vertical
        previewStack.spacing = 14
        previewStack.alignment = .fill
        previewStack.addArrangedSubview(leadingColumn)
        previewStack.addArrangedSubview(trailingColumn)

        previewCard.addSubview(title)
        previewCard.addSubview(previewStack)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),

            previewStack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            previewStack.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            previewStack.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),
            previewStack.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -18),
        ])
    }

    private func makePreviewColumn(
        speaker: String,
        side: DialogueSpeakerSide,
        bubble: DialogueJapaneseBubbleView
    ) -> UIView {
        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = speaker
        speakerLabel.textAlignment = side == .trailing ? .right : .left

        let column = UIStackView(arrangedSubviews: [speakerLabel, bubble])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = side == .leading ? .leading : .trailing
        return column
    }

    private func makeSampleBubble(
        text: String,
        highlight: String,
        side: DialogueSpeakerSide
    ) -> DialogueJapaneseBubbleView {
        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: label,
            text: text,
            font: Self.sampleFont,
            textColor: .label
        )
        let bubble = DialogueJapaneseBubbleView(label: label)
        bubble.setBackgroundStyle(.glass)
        bubble.setTailEdge(.none)
        bubble.setEmphasis(1)
        bubble.setUnderglowConfiguration(.forSpeaker(side))
        applySampleHighlight(on: bubble, text: text, highlight: highlight, side: side)
        return bubble
    }

    private func applySampleHighlight(
        on bubble: DialogueJapaneseBubbleView,
        text: String,
        highlight: String,
        side: DialogueSpeakerSide
    ) {
        let nsText = text as NSString
        let range = nsText.range(of: highlight)
        guard range.location != NSNotFound else { return }
        bubble.label.setTokenHighlightPreservingLayout(
            foregroundColor: .label,
            highlightedRange: range,
            fullHeight: ExperimentSettings.dialogueTokenSyncHighlightStyle == .full,
            highlightColor: ExperimentSettings.dialogueHighlightColor(for: side).tokenHighlightUIColor
        )
    }

    private func rebuildPresetButtons() {
        presetButtons.forEach { $0.removeFromSuperview() }
        presetButtons = []
        for preset in DialogueHighlightColorPreset.allCases {
            let button = makePresetButton(for: preset)
            presetStack.addArrangedSubview(button)
            presetButtons.append(button)
        }
    }

    private func makePresetButton(for preset: DialogueHighlightColorPreset) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 72)
        config.background.cornerRadius = 16
        config.background.backgroundColor = ExperimentPalette.cardSurface
        config.baseForegroundColor = .label

        config.attributedTitle = AttributedString(
            preset.title,
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold),
            ])
        )
        config.attributedSubtitle = AttributedString(
            preset.subtitle,
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.secondaryLabel,
            ])
        )
        config.titleAlignment = .leading

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = ExperimentCardStroke.normalWidth
        button.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        button.contentHorizontalAlignment = .leading
        button.tag = DialogueHighlightColorPreset.allCases.firstIndex(of: preset) ?? 0
        button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = "\(preset.title), \(preset.subtitle)"

        let swatches = makeSwatchPair(leading: preset.leading, trailing: preset.trailing)
        swatches.translatesAutoresizingMaskIntoConstraints = false
        swatches.isUserInteractionEnabled = false
        button.addSubview(swatches)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            swatches.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            swatches.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
        ])
        return button
    }

    private func makeSwatchPair(
        leading: DialogueBubbleUnderglowColor,
        trailing: DialogueBubbleUnderglowColor
    ) -> UIView {
        let leadingDot = makeSwatch(color: leading.uiColor)
        let trailingDot = makeSwatch(color: trailing.uiColor)
        let stack = UIStackView(arrangedSubviews: [leadingDot, trailingDot])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func makeSwatch(color: UIColor) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = color
        view.layer.cornerRadius = 11
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.label.withAlphaComponent(0.12).cgColor
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 22),
            view.heightAnchor.constraint(equalToConstant: 22),
        ])
        return view
    }

    private func refreshPreview() {
        leadingBubble.setUnderglowConfiguration(.forSpeaker(.leading))
        trailingBubble.setUnderglowConfiguration(.forSpeaker(.trailing))
        applySampleHighlight(
            on: leadingBubble,
            text: Self.leadingSample,
            highlight: Self.leadingHighlight,
            side: .leading
        )
        applySampleHighlight(
            on: trailingBubble,
            text: Self.trailingSample,
            highlight: Self.trailingHighlight,
            side: .trailing
        )
    }

    private func refreshPresetSelection() {
        let selected = DialogueHighlightColorPreset.matching(
            leading: ExperimentSettings.dialogueHighlightLeadingColor,
            trailing: ExperimentSettings.dialogueHighlightTrailingColor
        )
        for (index, button) in presetButtons.enumerated() {
            let preset = DialogueHighlightColorPreset.allCases[index]
            let isOn = preset == selected
            button.layer.borderWidth = isOn
                ? ExperimentCardStroke.emphasisWidth
                : ExperimentCardStroke.normalWidth
            button.layer.borderColor = isOn
                ? ExperimentPalette.highlightBorder.cgColor
                : ExperimentPalette.cardBorder.cgColor
            button.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }

    @objc private func presetTapped(_ sender: UIButton) {
        let presets = DialogueHighlightColorPreset.allCases
        guard presets.indices.contains(sender.tag) else { return }
        ExperimentSettings.applyDialogueHighlightPreset(presets[sender.tag])
        UISelectionFeedbackGenerator().selectionChanged()
        refreshPreview()
        refreshPresetSelection()
        onChange?()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        refreshPresetSelection()
        for button in presetButtons {
            if button.layer.borderWidth == ExperimentCardStroke.normalWidth {
                button.layer.borderColor = ExperimentPalette.cardBorder.cgColor
            }
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
