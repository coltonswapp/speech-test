//
//  DialogueTokenHighlightPreviewViewController.swift
//  shizen
//
//  Live preview of the spoken-word marker: underline vs full-height wash.
//

import UIKit

final class DialogueTokenHighlightPreviewViewController: UIViewController {

    var onChange: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let introLabel = UILabel()
    private let previewCard = UIView()
    private var sampleBubble: DialogueJapaneseBubbleView!
    private let choiceStack = UIStackView()
    private var choiceButtons: [UIButton] = []

    private static let sample = "駅はどこですか？"
    private static let sampleHighlight = "どこ"
    private static let sampleFont = UIFont.systemFont(ofSize: 22, weight: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Token highlight"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        configureLayout()
        rebuildChoices()
        refreshPreview()
        refreshChoiceSelection()
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
        introLabel.text = "The marker behind the word being spoken. The example uses the same highlight as dialogue playback."

        configurePreviewCard()

        let choicesHeader = UILabel()
        choicesHeader.font = .preferredFont(forTextStyle: .headline)
        choicesHeader.text = "Style"

        choiceStack.axis = .vertical
        choiceStack.spacing = 10

        contentStack.addArrangedSubview(introLabel)
        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(choicesHeader)
        contentStack.addArrangedSubview(choiceStack)

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

        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        sampleBubble = DialogueJapaneseBubbleView(label: label)

        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = "A"

        let column = UIStackView(arrangedSubviews: [speakerLabel, sampleBubble])
        column.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = 6
        column.alignment = .leading

        previewCard.addSubview(title)
        previewCard.addSubview(column)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),

            column.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            column.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(lessThanOrEqualTo: previewCard.trailingAnchor, constant: -16),
            column.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -18),
        ])
    }

    private func rebuildChoices() {
        choiceButtons.forEach { $0.removeFromSuperview() }
        choiceButtons = DialogueTokenSyncHighlightStyle.allCases.enumerated().map { index, style in
            let button = makeChoiceButton(style: style, tag: index)
            choiceStack.addArrangedSubview(button)
            return button
        }
    }

    private func makeChoiceButton(style: DialogueTokenSyncHighlightStyle, tag: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        config.background.cornerRadius = 16
        config.background.backgroundColor = ExperimentPalette.cardSurface
        config.baseForegroundColor = .label
        config.attributedTitle = AttributedString(
            style.title,
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold),
            ])
        )
        config.attributedSubtitle = AttributedString(
            style.subtitle,
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ])
        )
        config.titleAlignment = .leading

        let button = UIButton(configuration: config)
        button.tag = tag
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: #selector(choiceTapped(_:)), for: .touchUpInside)
        return button
    }

    private func refreshPreview() {
        let style = ExperimentSettings.dialogueTokenSyncHighlightStyle
        let highlightColor = ExperimentSettings.dialogueHighlightColor(for: .leading).tokenHighlightUIColor
        sampleBubble.setTailEdge(.none)
        sampleBubble.setSolidFillStaysVisible(false)
        sampleBubble.setBackgroundStyle(.glass)
        sampleBubble.setUnderglowConfiguration(.forSpeaker(.leading))
        sampleBubble.setEmphasis(1)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: sampleBubble.label,
            text: Self.sample,
            font: Self.sampleFont,
            textColor: .label
        )
        let range = (Self.sample as NSString).range(of: Self.sampleHighlight)
        guard range.location != NSNotFound else { return }
        sampleBubble.label.setTokenHighlightPreservingLayout(
            foregroundColor: .label,
            highlightedRange: range,
            fullHeight: style == .full,
            highlightColor: highlightColor
        )
    }

    private func refreshChoiceSelection() {
        let selected = ExperimentSettings.dialogueTokenSyncHighlightStyle
        for (index, button) in choiceButtons.enumerated() {
            let isOn = DialogueTokenSyncHighlightStyle.allCases[index] == selected
            button.layer.borderWidth = isOn
                ? ExperimentCardStroke.emphasisWidth
                : ExperimentCardStroke.normalWidth
            button.layer.borderColor = isOn
                ? ExperimentPalette.highlightBorder.resolvedColor(with: traitCollection).cgColor
                : ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
            button.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }

    @objc private func choiceTapped(_ sender: UIButton) {
        let styles = DialogueTokenSyncHighlightStyle.allCases
        guard styles.indices.contains(sender.tag) else { return }
        let style = styles[sender.tag]
        guard style != ExperimentSettings.dialogueTokenSyncHighlightStyle else { return }
        ExperimentSettings.dialogueTokenSyncHighlightStyle = style
        UISelectionFeedbackGenerator().selectionChanged()
        refreshPreview()
        refreshChoiceSelection()
        onChange?()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        refreshPreview()
        refreshChoiceSelection()
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
