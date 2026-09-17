//
//  KanjiSpotlightHighlightColorPickerViewController.swift
//  shizen
//
//  Sheet of highlight washes for the subject kanji on Kanji Spotlight example
//  slides. Same palette as Dialogue Recording karaoke.
//

import UIKit

final class KanjiSpotlightHighlightColorPickerViewController: UIViewController {

    var onChange: (() -> Void)?

    private let previewExpression: String
    private let previewHighlight: String
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let introLabel = UILabel()
    private let previewCard = UIView()
    private let previewWordLabel = FuriganaTranscriptLabel()
    private let colorStack = UIStackView()
    private var colorButtons: [UIButton] = []

    private let previewFont = UIFont.systemFont(ofSize: 34, weight: .bold)

    init(previewExpression: String, previewHighlight: String) {
        self.previewExpression = previewExpression
        self.previewHighlight = previewHighlight
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Highlight color"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        configureLayout()
        rebuildColorButtons()
        refreshPreview()
        refreshSelection()
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
        introLabel.text = "Pick the wash behind the spotlighted kanji in each example."

        configurePreviewCard()

        let colorsHeader = UILabel()
        colorsHeader.font = .preferredFont(forTextStyle: .headline)
        colorsHeader.text = "Colors"

        colorStack.axis = .vertical
        colorStack.spacing = 10

        contentStack.addArrangedSubview(introLabel)
        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(colorsHeader)
        contentStack.addArrangedSubview(colorStack)

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

        previewWordLabel.translatesAutoresizingMaskIntoConstraints = false
        previewWordLabel.numberOfLines = 1
        previewWordLabel.textAlignment = .center
        previewWordLabel.clipsToBounds = false

        previewCard.addSubview(title)
        previewCard.addSubview(previewWordLabel)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),

            previewWordLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            previewWordLabel.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            previewWordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previewCard.leadingAnchor, constant: 16),
            previewWordLabel.trailingAnchor.constraint(lessThanOrEqualTo: previewCard.trailingAnchor, constant: -16),
            previewWordLabel.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -18),
        ])
    }

    private func refreshPreview() {
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: previewWordLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: previewExpression,
                font: previewFont,
                textColor: .label
            ),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: previewFont),
                left: 0,
                bottom: 2,
                right: 0
            )
        )
        let range = (previewExpression as NSString).range(of: previewHighlight)
        guard range.location != NSNotFound else { return }
        previewWordLabel.setTokenHighlightPreservingLayout(
            foregroundColor: .label,
            highlightedRange: range,
            fullHeight: true,
            highlightColor: ExperimentSettings.kanjiSpotlightHighlightColor.tokenHighlightUIColor
        )
    }

    private func rebuildColorButtons() {
        colorButtons.forEach { $0.removeFromSuperview() }
        colorButtons = []
        for color in DialogueBubbleUnderglowColor.allCases {
            let button = makeColorButton(color: color)
            colorStack.addArrangedSubview(button)
            colorButtons.append(button)
        }
    }

    private func makeColorButton(color: DialogueBubbleUnderglowColor) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 52)
        config.background.cornerRadius = 16
        config.background.backgroundColor = ExperimentPalette.cardSurface
        config.baseForegroundColor = .label
        config.attributedTitle = AttributedString(
            color.title,
            attributes: AttributeContainer([
                .font: UIFont.systemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                    weight: .semibold
                ),
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
        button.tag = color.rawValue
        button.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = color.title

        let swatch = makeSwatch(color: color.uiColor)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.isUserInteractionEnabled = false
        button.addSubview(swatch)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            swatch.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            swatch.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
        ])
        return button
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

    private func refreshSelection() {
        let selected = ExperimentSettings.kanjiSpotlightHighlightColor
        for button in colorButtons {
            let isOn = button.tag == selected.rawValue
            button.layer.borderWidth = isOn
                ? ExperimentCardStroke.emphasisWidth
                : ExperimentCardStroke.normalWidth
            button.layer.borderColor = isOn
                ? ExperimentPalette.highlightBorder.cgColor
                : ExperimentPalette.cardBorder.cgColor
            button.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }

    @objc private func colorTapped(_ sender: UIButton) {
        guard let color = DialogueBubbleUnderglowColor(rawValue: sender.tag) else { return }
        ExperimentSettings.kanjiSpotlightHighlightColor = color
        UISelectionFeedbackGenerator().selectionChanged()
        refreshPreview()
        refreshSelection()
        onChange?()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        refreshSelection()
        refreshPreview()
        for button in colorButtons {
            if button.layer.borderWidth == ExperimentCardStroke.normalWidth {
                button.layer.borderColor = ExperimentPalette.cardBorder.cgColor
            }
        }
    }
}
