//
//  GrammarExampleStepViewController.swift
//  shizen
//

import InteractionKit
import UIKit

final class GrammarExampleStepViewController: LessonStepViewController {

    var onStepResult: ((Bool) -> Void)?

    private let example: GrammarExample
    private let pointTitle: String
    private let audioPlayer = GrammarAudioPlayer()

    private let scenarioView = GrammarExampleScenarioView()
    private let scrubbableSentenceView = ScrubbableSentenceView(engine: JapaneseScrubSentenceEngine.shared)
    private let englishLabel = UILabel()
    private let replayControl = LessonAudioReplayButton(size: 52, glyphPointSize: 22, glyphDimension: 26)
    private let sentenceSectionRowStack = UIStackView()
    private let sentenceContentStack = UIStackView()

    init(example: GrammarExample, pointTitle: String) {
        self.example = example
        self.pointTitle = pointTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        configureCTA(.continue_(), target: self, action: #selector(continueTapped))
        progressiveContainerCoordinator?.setLivesVisible(false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        audioPlayer.stop()
        scrubbableSentenceView.dismissCalloutOnly(animated: false)
    }

    private func buildUI() {
        let shortTitle = pointTitle.split(separator: "・").first.map(String.init) ?? pointTitle
        configureInstruction("Example · \(shortTitle)")

        let font = GrammarJapaneseTypography.scrubbableFeaturedFont
        let hasScenario = example.scenario.map { !$0.lines.isEmpty } ?? false

        scrubbableSentenceView.showCalloutOnScrub = true
        scrubbableSentenceView.sentenceLineView.textAlignment = .natural
        scrubbableSentenceView.onRequestDictionaryDetail = { [weak self] surface, sentence in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.present(surface: surface, sentence: sentence, from: self)
        }
        scrubbableSentenceView.configure(sentence: example.japanese, font: font, showsFurigana: true)
        scrubbableSentenceView.bindDismissOnTap(view)

        englishLabel.font = .preferredFont(forTextStyle: .body)
        englishLabel.textAlignment = .natural
        englishLabel.numberOfLines = 0
        englishLabel.textColor = .label
        englishLabel.text = example.english

        sentenceContentStack.axis = .vertical
        sentenceContentStack.alignment = .leading
        sentenceContentStack.spacing = 8
        sentenceContentStack.addArrangedSubview(scrubbableSentenceView)
        sentenceContentStack.addArrangedSubview(englishLabel)

        sentenceContentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sentenceContentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sentenceSectionRowStack.axis = .horizontal
        sentenceSectionRowStack.alignment = .top
        sentenceSectionRowStack.spacing = 16
        sentenceSectionRowStack.distribution = .fill
        sentenceSectionRowStack.addArrangedSubview(sentenceContentStack)
        sentenceSectionRowStack.addArrangedSubview(replayControl)

        replayControl.setContentHuggingPriority(.required, for: .horizontal)
        replayControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        replayControl.addTarget(self, action: #selector(playTapped))

        NSLayoutConstraint.activate([
            replayControl.topAnchor.constraint(
                equalTo: scrubbableSentenceView.sentenceLineView.topAnchor
            ),
        ])

        if hasScenario, let scenario = example.scenario {
            scenarioView.configure(scenario: scenario, example: example) { [weak self] in
                guard let self else { return }
                DialogueExperimentSheetPresenter.present(
                    from: self,
                    pointTitle: self.pointTitle,
                    example: self.example
                )
            }
        } else {
            scenarioView.isHidden = true
        }

        var contentViews: [UIView] = [sentenceSectionRowStack]
        if hasScenario {
            contentViews.append(scenarioView)
        }

        let stack = makeLessonContentStack(belowInstruction: contentViews, spacing: 16)
        if hasScenario {
            stack.setCustomSpacing(20, after: sentenceSectionRowStack)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        installLessonContent(stack, pinsBelowLessonHeader: true)
    }

    @objc private func playTapped() {
        let dialogueLines = GrammarExampleDialogueLines.lines(for: example)
        audioPlayer.play(
            publishedAudioUrl: example.publishedAudioUrl,
            audioKey: example.audioKey,
            cacheMetadata: example.remoteAudioCacheMetadata,
            dialogueLines: dialogueLines,
            fallbackText: example.japanese
        )
    }

    @objc private func continueTapped() {
        onStepResult?(true)
        advanceToNextStep()
    }
}
