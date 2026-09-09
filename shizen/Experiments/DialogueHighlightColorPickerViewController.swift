//
//  DialogueHighlightColorPickerViewController.swift
//  shizen
//
//  Sheet of left/right color presets for Dialogue Recording. Glass previews
//  underglow + token karaoke; Messages previews solid fills, tails, and karaoke.
//

import UIKit

final class DialogueHighlightColorPickerViewController: UIViewController {

    var onChange: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let introLabel = UILabel()
    private let styleControl = UISegmentedControl(
        items: DialogueContentBubbleStyle.allCases.map(\.title)
    )
    private let previewCard = UIView()
    private let previewStack = UIStackView()
    private var leadingBubble: DialogueJapaneseBubbleView!
    private var trailingBubble: DialogueJapaneseBubbleView!
    private let presetStack = UIStackView()
    private var presetButtons: [UIButton] = []
    private var previewStyle: DialogueContentBubbleStyle = ExperimentSettings.dialogueContentBubbleStyle

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
        refreshIntro()
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

        introLabel.font = .preferredFont(forTextStyle: .subheadline)
        introLabel.textColor = .secondaryLabel
        introLabel.numberOfLines = 0

        styleControl.selectedSegmentIndex = DialogueContentBubbleStyle.allCases
            .firstIndex(of: previewStyle) ?? 0
        styleControl.addTarget(self, action: #selector(styleChanged), for: .valueChanged)

        configurePreviewCard()

        let presetsHeader = UILabel()
        presetsHeader.font = .preferredFont(forTextStyle: .headline)
        presetsHeader.text = "Presets"

        presetStack.axis = .vertical
        presetStack.spacing = 10

        contentStack.addArrangedSubview(introLabel)
        contentStack.addArrangedSubview(styleControl)
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
        applyChrome(to: bubble, text: text, highlight: highlight, side: side)
        return bubble
    }

    private func applyChrome(
        to bubble: DialogueJapaneseBubbleView,
        text: String,
        highlight: String,
        side: DialogueSpeakerSide
    ) {
        let textColor: UIColor
        let highlightColor: UIColor
        switch previewStyle {
        case .glass:
            bubble.setTailEdge(.none)
            bubble.setSolidFillStaysVisible(false)
            bubble.setBackgroundStyle(.glass)
            bubble.setUnderglowConfiguration(.forSpeaker(side))
            textColor = .label
            highlightColor = ExperimentSettings.dialogueHighlightColor(for: side).tokenHighlightUIColor
        case .messages:
            let color = ExperimentSettings.dialogueMessageColor(for: side)
            bubble.setBackgroundStyle(.solid)
            bubble.setSolidFillStaysVisible(true)
            bubble.setSolidFillColor(color.messageFillUIColor)
            bubble.setTailEdge(side == .leading ? .leading : .trailing)
            textColor = color.messageTextUIColor
            highlightColor = color.messageTokenHighlightUIColor
        }
        bubble.setEmphasis(1)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: bubble.label,
            text: text,
            font: Self.sampleFont,
            textColor: textColor
        )
        applySampleHighlight(
            on: bubble,
            text: text,
            highlight: highlight,
            textColor: textColor,
            highlightColor: highlightColor
        )
    }

    private func applySampleHighlight(
        on bubble: DialogueJapaneseBubbleView,
        text: String,
        highlight: String,
        textColor: UIColor,
        highlightColor: UIColor
    ) {
        let nsText = text as NSString
        let range = nsText.range(of: highlight)
        guard range.location != NSNotFound else { return }
        bubble.label.setTokenHighlightPreservingLayout(
            foregroundColor: textColor,
            highlightedRange: range,
            fullHeight: ExperimentSettings.dialogueTokenSyncHighlightStyle == .full,
            highlightColor: highlightColor
        )
    }

    private func rebuildPresetButtons() {
        presetButtons.forEach { $0.removeFromSuperview() }
        presetButtons = []
        for (index, preset) in currentPresets.enumerated() {
            let button = makePresetButton(title: preset.title, subtitle: preset.subtitle, leading: preset.leading, trailing: preset.trailing, tag: index)
            presetStack.addArrangedSubview(button)
            presetButtons.append(button)
        }
    }

    private func makePresetButton(
        title: String,
        subtitle: String,
        leading: DialogueBubbleUnderglowColor,
        trailing: DialogueBubbleUnderglowColor,
        tag: Int
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 72)
        config.background.cornerRadius = 16
        config.background.backgroundColor = ExperimentPalette.cardSurface
        config.baseForegroundColor = .label

        config.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold),
            ])
        )
        config.attributedSubtitle = AttributedString(
            subtitle,
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
        button.tag = tag
        button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = "\(title), \(subtitle)"

        let swatches = makeSwatchPair(leading: leading, trailing: trailing)
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
        let leadingDot = makeSwatch(color: swatchColor(for: leading))
        let trailingDot = makeSwatch(color: swatchColor(for: trailing))
        let stack = UIStackView(arrangedSubviews: [leadingDot, trailingDot])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func swatchColor(for color: DialogueBubbleUnderglowColor) -> UIColor {
        switch previewStyle {
        case .glass: return color.uiColor
        case .messages: return color == .gray ? color.uiColor : color.messageFillUIColor
        }
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

    private var currentPresets: [(title: String, subtitle: String, leading: DialogueBubbleUnderglowColor, trailing: DialogueBubbleUnderglowColor)] {
        switch previewStyle {
        case .glass:
            return DialogueHighlightColorPreset.allCases.map {
                ($0.title, $0.subtitle, $0.leading, $0.trailing)
            }
        case .messages:
            return DialogueMessageColorPreset.allCases.map {
                ($0.title, $0.subtitle, $0.leading, $0.trailing)
            }
        }
    }

    private func refreshIntro() {
        switch previewStyle {
        case .glass:
            introLabel.text = "Pick a preset for each side’s underglow and spoken-word highlight."
        case .messages:
            introLabel.text = "Pick a preset for each side’s bubble color and spoken-word highlight."
        }
    }

    private func refreshPreview() {
        applyChrome(
            to: leadingBubble,
            text: Self.leadingSample,
            highlight: Self.leadingHighlight,
            side: .leading
        )
        applyChrome(
            to: trailingBubble,
            text: Self.trailingSample,
            highlight: Self.trailingHighlight,
            side: .trailing
        )
    }

    private func refreshPresetSelection() {
        let selectedIndex: Int?
        switch previewStyle {
        case .glass:
            selectedIndex = DialogueHighlightColorPreset.matching(
                leading: ExperimentSettings.dialogueHighlightLeadingColor,
                trailing: ExperimentSettings.dialogueHighlightTrailingColor
            ).flatMap { DialogueHighlightColorPreset.allCases.firstIndex(of: $0) }
        case .messages:
            selectedIndex = DialogueMessageColorPreset.matching(
                leading: ExperimentSettings.dialogueMessageLeadingColor,
                trailing: ExperimentSettings.dialogueMessageTrailingColor
            ).flatMap { DialogueMessageColorPreset.allCases.firstIndex(of: $0) }
        }
        for (index, button) in presetButtons.enumerated() {
            let isOn = index == selectedIndex
            button.layer.borderWidth = isOn
                ? ExperimentCardStroke.emphasisWidth
                : ExperimentCardStroke.normalWidth
            button.layer.borderColor = isOn
                ? ExperimentPalette.highlightBorder.cgColor
                : ExperimentPalette.cardBorder.cgColor
            button.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }

    @objc private func styleChanged() {
        let styles = DialogueContentBubbleStyle.allCases
        guard styles.indices.contains(styleControl.selectedSegmentIndex) else { return }
        previewStyle = styles[styleControl.selectedSegmentIndex]
        UISelectionFeedbackGenerator().selectionChanged()
        refreshIntro()
        rebuildPresetButtons()
        refreshPreview()
        refreshPresetSelection()
    }

    @objc private func presetTapped(_ sender: UIButton) {
        switch previewStyle {
        case .glass:
            let presets = DialogueHighlightColorPreset.allCases
            guard presets.indices.contains(sender.tag) else { return }
            ExperimentSettings.applyDialogueHighlightPreset(presets[sender.tag])
        case .messages:
            let presets = DialogueMessageColorPreset.allCases
            guard presets.indices.contains(sender.tag) else { return }
            ExperimentSettings.applyDialogueMessageColorPreset(presets[sender.tag])
        }
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
