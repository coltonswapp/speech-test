//
//  KanaVocabAssociationStepViewController.swift
//  shizen
//
//  Shows example vocabulary starting with a newly discovered kana.
//

import UIKit

final class KanaVocabAssociationStepViewController: LessonStepViewController {

    private let glyph: KanaGlyph
    private let script: KanaScript
    private let examples: [KanaVocabExample]
    private var stepIndex: Int
    private var totalSteps: Int
    private let pronunciationPlayer = KanaPronunciationPlayer()

    init(
        glyph: KanaGlyph,
        script: KanaScript,
        stepIndex: Int = 0,
        totalSteps: Int = 1
    ) {
        self.glyph = glyph
        self.script = script
        self.examples = KanaDetailCatalog.vocabularyExamples(
            for: glyph.kana,
            romaji: glyph.romaji,
            maxCount: 4
        )
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStepIndex(_ stepIndex: Int, totalSteps: Int) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pronunciationPlayer.stop()
    }

    private func buildUI() {
        let displayKana = script == .katakana
            ? KanaCurriculum.hiraganaToKatakana(glyph.kana)
            : glyph.kana

        let headlineLabel = UILabel()
        headlineLabel.attributedText = Self.headlineText(displayKana: displayKana)
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0

        configureInstruction("These words can help you remember the sound.")

        let wordsStack = UIStackView()
        wordsStack.axis = .vertical
        wordsStack.spacing = 10
        wordsStack.alignment = .fill

        if examples.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No example words yet for this character."
            emptyLabel.font = .preferredFont(forTextStyle: .body)
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            wordsStack.addArrangedSubview(emptyLabel)
        } else {
            for example in examples {
                wordsStack.addArrangedSubview(makeWordRow(for: example))
            }
        }

        let stack = makeLessonContentStack(
            belowInstruction: [headlineLabel, wordsStack],
            afterInstructionSpacing: 12
        )
        stack.setCustomSpacing(24, after: headlineLabel)

        configureCTA(.next(), target: self, action: #selector(nextTapped))
        installLessonContent(stack, horizontalInset: LessonStepLayout.instructionHeaderHorizontalInset)
    }

    private func makeWordRow(for example: KanaVocabExample) -> UIView {
        let card = UIView()
        card.backgroundColor = ExperimentPalette.cardSurface
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let japaneseLabel = UILabel()
        japaneseLabel.text = example.japanese
        japaneseLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        japaneseLabel.textColor = .label

        let detailLabel = UILabel()
        detailLabel.text = "\(example.romaji) · \(example.meaning)"
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [japaneseLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let playControl = LessonAudioReplayButton(
            size: 40,
            glyphPointSize: 17,
            glyphDimension: 22,
            accessibilityLabel: "Play \(example.japanese)"
        )
        playControl.addAction(UIAction { [weak self] _ in
            self?.playWord(example.japanese)
        })

        card.addSubview(textStack)
        card.addSubview(playControl)
        NSLayoutConstraint.activate([
            playControl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            playControl.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: playControl.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        return card
    }

    private func playWord(_ japanese: String) {
        pronunciationPlayer.stop()
        pronunciationPlayer.play(kana: japanese, languageIdentifier: "ja-JP")
    }

    @objc private func nextTapped() {
        advanceToNextStep()
    }

    private static func headlineText(displayKana: String) -> NSAttributedString {
        let prefix = "Words that start with "
        let metrics = UIFontMetrics(forTextStyle: .title2)
        let baseSize = UIFont.preferredFont(forTextStyle: .title2).pointSize

        let bodyFont = metrics.scaledFont(for: .systemFont(ofSize: baseSize, weight: .bold))
        let kanaFont = metrics.scaledFont(for: .systemFont(ofSize: baseSize * 1.12, weight: .heavy))

        let text = NSMutableAttributedString(
            string: prefix,
            attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
        )
        text.append(NSAttributedString(
            string: displayKana,
            attributes: [.font: kanaFont, .foregroundColor: UIColor.label]
        ))
        return text
    }
}
