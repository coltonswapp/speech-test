//
//  KanaPairMatchStepViewController.swift
//  shizen
//
//  One lesson step: tap to match four kana ↔ romaji pairs in two columns.
//

import UIKit

private enum KanaPairMatchStepStyle {
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 11
    static let horizontalInset: CGFloat = 20
    static let headerSpacing: CGFloat = 20
}

private enum KanaPairMatchStepMotion {
    static let successCascadeStagger: TimeInterval = 0.09
    static let pairMatchChimeLead: TimeInterval = 0.04
}

private struct KanaPairMatchTileSpec: Hashable {
    enum Column { case left, right }

    let pairID: String
    let displayText: String
    let labelStyle: KanaChoiceButtonLabelStyle
    let column: Column
    let speaksKana: String?
}

enum KanaPairMatchStepKind {
    case kanaGlyphs
    case words
}

final class KanaPairMatchStepViewController: LessonStepViewController {

    var onStepComplete: (([String]) -> Void)?

    private let round: KanaPairMatchRound
    private let kind: KanaPairMatchStepKind
    private var stepIndex: Int
    private var totalSteps: Int

    private var matchedPairIDs: Set<String> = []
    private var selectedTileSpec: KanaPairMatchTileSpec?
    private var tileButtons: [KanaPairMatchTileSpec: KanaChoiceButton] = [:]
    private var pairMatchCascadeGeneration = 0
    private var didReportCompletion = false

    private let pronunciationPlayer = KanaPronunciationPlayer()

    private let columnsStack = UIStackView()
    private let leftColumnStack = UIStackView()
    private let rightColumnStack = UIStackView()

    init(
        round: KanaPairMatchRound,
        kind: KanaPairMatchStepKind = .kanaGlyphs,
        stepIndex: Int = 0,
        totalSteps: Int = 1
    ) {
        self.round = round
        self.kind = kind
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
        ExperimentFeedbackSound.prepareClick()
        buildUI()
        loadBoard()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pronunciationPlayer.stop()
    }

    private func buildUI() {
        leftColumnStack.axis = .vertical
        leftColumnStack.spacing = KanaPairMatchStepStyle.rowSpacing
        leftColumnStack.distribution = .fillEqually

        rightColumnStack.axis = .vertical
        rightColumnStack.spacing = KanaPairMatchStepStyle.rowSpacing
        rightColumnStack.distribution = .fillEqually

        columnsStack.axis = .horizontal
        columnsStack.spacing = KanaPairMatchStepStyle.columnSpacing
        columnsStack.alignment = .fill
        columnsStack.distribution = .fillEqually
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        columnsStack.addArrangedSubview(leftColumnStack)
        columnsStack.addArrangedSubview(rightColumnStack)

        contentView.addSubview(columnsStack)

        configureCTA(.next(style: .blue), target: self, action: #selector(nextTapped))
        primaryButton.isEnabled = false

        let instructionBottom = installInstructionHeader(
            horizontalInset: KanaPairMatchStepStyle.horizontalInset
        )

        NSLayoutConstraint.activate([
            columnsStack.topAnchor.constraint(
                equalTo: instructionBottom,
                constant: KanaPairMatchStepStyle.headerSpacing
            ),
            columnsStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: KanaPairMatchStepStyle.horizontalInset
            ),
            columnsStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -KanaPairMatchStepStyle.horizontalInset
            ),
            columnsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    private func loadBoard() {
        matchedPairIDs.removeAll()
        selectedTileSpec = nil
        tileButtons.removeAll()
        pairMatchCascadeGeneration += 1
        primaryButton.isEnabled = false
        updateInstruction()

        let leftSpecs = shuffledTileSpecs(column: .left)
        let rightSpecs = shuffledTileSpecs(column: .right)
        rebuildColumn(leftColumnStack, specs: leftSpecs)
        rebuildColumn(rightColumnStack, specs: rightSpecs)
    }

    private func updateInstruction() {
        switch (kind, round.sideLayout) {
        case (.kanaGlyphs, .kanaOnLeft):
            configureInstruction("Match each kana to its romaji")
        case (.kanaGlyphs, .romajiOnLeft):
            configureInstruction("Match each romaji to its kana")
        case (.words, .kanaOnLeft):
            configureInstruction("Match each word to its romaji")
        case (.words, .romajiOnLeft):
            configureInstruction("Match each romaji to its word")
        }
    }

    private func shuffledTileSpecs(column: KanaPairMatchTileSpec.Column) -> [KanaPairMatchTileSpec] {
        let kanaOnLeft = round.sideLayout == .kanaOnLeft
        let specs = round.pairs.map { pair -> KanaPairMatchTileSpec in
            switch column {
            case .left:
                if kanaOnLeft {
                    return KanaPairMatchTileSpec(
                        pairID: pair.pairID,
                        displayText: pair.kana,
                        labelStyle: .kana,
                        column: .left,
                        speaksKana: pair.speaksKana
                    )
                }
                return KanaPairMatchTileSpec(
                    pairID: pair.pairID,
                    displayText: pair.romaji,
                    labelStyle: .romaji,
                    column: .left,
                    speaksKana: nil
                )
            case .right:
                if kanaOnLeft {
                    return KanaPairMatchTileSpec(
                        pairID: pair.pairID,
                        displayText: pair.romaji,
                        labelStyle: .romaji,
                        column: .right,
                        speaksKana: nil
                    )
                }
                return KanaPairMatchTileSpec(
                    pairID: pair.pairID,
                    displayText: pair.kana,
                    labelStyle: .kana,
                    column: .right,
                    speaksKana: pair.speaksKana
                )
            }
        }
        return specs.shuffled()
    }

    private func rebuildColumn(_ stack: UIStackView, specs: [KanaPairMatchTileSpec]) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for spec in specs {
            let button = KanaChoiceButton(value: spec.displayText, labelStyle: spec.labelStyle)
            button.addAction(UIAction { [weak self] _ in
                self?.tileTapped(spec)
            }, for: .touchUpInside)
            tileButtons[spec] = button
            stack.addArrangedSubview(button)
        }
    }

    private func tileTapped(_ spec: KanaPairMatchTileSpec) {
        guard !matchedPairIDs.contains(spec.pairID) else { return }

        if selectedTileSpec == spec {
            setSelected(spec, chosen: false)
            selectedTileSpec = nil
            return
        }

        guard let selected = selectedTileSpec else {
            selectedTileSpec = spec
            setSelected(spec, chosen: true)
            return
        }

        if selected.column == spec.column {
            setSelected(selected, chosen: false)
            selectedTileSpec = spec
            setSelected(spec, chosen: true)
            return
        }

        if selected.pairID == spec.pairID {
            markPairMatched(selected, spec)
            selectedTileSpec = nil
            return
        }

        ExperimentFeedbackSound.playIncorrect()
        setSelected(selected, chosen: false)
        selectedTileSpec = spec
        setSelected(spec, chosen: true)
    }

    private func setSelected(_ spec: KanaPairMatchTileSpec, chosen: Bool) {
        tileButtons[spec]?.setChosen(chosen)
    }

    private func markPairMatched(_ first: KanaPairMatchTileSpec, _ second: KanaPairMatchTileSpec) {
        matchedPairIDs.insert(first.pairID)

        tileButtons[first]?.setChosen(false, animated: false)
        tileButtons[second]?.setChosen(false, animated: false)

        playPairMatchCascade(first: first, second: second)
        checkBoardComplete()
    }

    private func playPairMatchCascade(first: KanaPairMatchTileSpec, second: KanaPairMatchTileSpec) {
        pairMatchCascadeGeneration += 1
        let generation = pairMatchCascadeGeneration
        let specs = [first, second]
        let successSound = ExperimentFeedbackSound.prepareSuccess(for: .kanaSoundMatch)
        let chimeKeyTime = KanaSoundMatchMetrics.successChimeKeyTime
        let chimeLead = KanaPairMatchStepMotion.pairMatchChimeLead
        let stagger = KanaPairMatchStepMotion.successCascadeStagger

        if chimeLead > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() - chimeLead) { [weak self] in
                guard let self, generation == self.pairMatchCascadeGeneration else { return }
                ExperimentFeedbackSound.playPreparedSuccessSound(successSound)
            }
        }

        for (index, spec) in specs.enumerated() {
            let delay = Double(index) * stagger
            let playsChimeOnBounce = index == 0 && chimeLead == 0

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, generation == self.pairMatchCascadeGeneration else { return }
                guard let button = self.tileButtons[spec] else { return }

                if index == 0, let kana = first.speaksKana ?? second.speaksKana {
                    self.pronunciationPlayer.play(kana: kana, languageIdentifier: "ja-JP")
                }

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                button.animateSuccessBounce(
                    successSound: playsChimeOnBounce ? successSound : nil,
                    successChimeKeyTime: playsChimeOnBounce ? chimeKeyTime : nil
                )
            }
        }
    }

    private func checkBoardComplete() {
        guard matchedPairIDs.count == round.pairs.count else { return }
        configureInstruction("Nice — all pairs matched")
        primaryButton.isEnabled = true
    }

    @objc private func nextTapped() {
        guard primaryButton.isEnabled, !didReportCompletion else { return }
        didReportCompletion = true
        onStepComplete?(round.progressKana)
        advanceToNextStep()
    }
}
