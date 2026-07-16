//
//  KanaPairMatchExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: tap to match hiragana ↔ romaji in two columns of four tiles.
//

import UIKit

private enum KanaPairMatchStyle {
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 11
    static let horizontalInset: CGFloat = 20
    static let boardToButtonSpacing: CGFloat = 12
    static let buttonAreaHeight =
        PrimaryButton.preferredHeight
        + ProgressiveStepViewController.buttonBottomInset
        + boardToButtonSpacing
}

private enum KanaPairMatchMotion {
    static let fadeOutDuration: TimeInterval = 0.2
    static let fadeInDuration: TimeInterval = 0.25
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

final class KanaPairMatchExperimentViewController: UIViewController {

    private var roundIndex = 0
    private var matchedPairIDs: Set<String> = []
    private var selectedTileSpec: KanaPairMatchTileSpec?
    private var tileButtons: [KanaPairMatchTileSpec: KanaChoiceButton] = [:]
    private var leftTileSpecs: [KanaPairMatchTileSpec] = []
    private var rightTileSpecs: [KanaPairMatchTileSpec] = []
    private var pairMatchCascadeGeneration = 0

    private let pronunciationPlayer = KanaPronunciationPlayer()

    private let instructionLabel = UILabel()
    private let progressLabel = UILabel()
    private let boardLayoutGuide = UILayoutGuide()
    private let leftColumnStack = UIStackView()
    private let rightColumnStack = UIStackView()
    private let columnsStack = UIStackView()
    private let nextButton = PrimaryButton()

    private var currentRound: KanaPairMatchRound {
        KanaPairMatchRoundBank.rounds[roundIndex]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kana pair match"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        ExperimentFeedbackSound.prepareClick()
        buildUI()
        loadRound(animated: false)
    }

    private func buildUI() {
        LessonInstructionLabel.apply(to: instructionLabel)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = .preferredFont(forTextStyle: .footnote)
        progressLabel.textColor = .tertiaryLabel
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        leftColumnStack.axis = .vertical
        leftColumnStack.spacing = KanaPairMatchStyle.rowSpacing
        leftColumnStack.distribution = .fillEqually
        leftColumnStack.translatesAutoresizingMaskIntoConstraints = false

        rightColumnStack.axis = .vertical
        rightColumnStack.spacing = KanaPairMatchStyle.rowSpacing
        rightColumnStack.distribution = .fillEqually
        rightColumnStack.translatesAutoresizingMaskIntoConstraints = false

        columnsStack.axis = .horizontal
        columnsStack.spacing = KanaPairMatchStyle.columnSpacing
        columnsStack.alignment = .fill
        columnsStack.distribution = .fillEqually
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        columnsStack.addArrangedSubview(leftColumnStack)
        columnsStack.addArrangedSubview(rightColumnStack)

        nextButton.primaryStyle = .blue
        nextButton.setTitle("Next Round", for: .normal)
        nextButton.isEnabled = false
        nextButton.accessibilityLabel = "Next round"
        nextButton.addTarget(self, action: #selector(nextRoundTapped), for: .touchUpInside)

        view.addLayoutGuide(boardLayoutGuide)
        view.addSubview(instructionLabel)
        view.addSubview(progressLabel)
        view.addSubview(columnsStack)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: KanaPairMatchStyle.horizontalInset),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -KanaPairMatchStyle.horizontalInset),

            progressLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 6),
            progressLabel.leadingAnchor.constraint(equalTo: instructionLabel.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: instructionLabel.trailingAnchor),

            boardLayoutGuide.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 12),
            boardLayoutGuide.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -KanaPairMatchStyle.buttonAreaHeight
            ),
            boardLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            boardLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            columnsStack.centerYAnchor.constraint(equalTo: boardLayoutGuide.centerYAnchor),
            columnsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: KanaPairMatchStyle.horizontalInset),
            columnsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -KanaPairMatchStyle.horizontalInset),

            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            nextButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -ProgressiveStepViewController.buttonBottomInset
            ),
            nextButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    private func loadRound(animated: Bool) {
        matchedPairIDs.removeAll()
        selectedTileSpec = nil
        tileButtons.removeAll()
        pairMatchCascadeGeneration += 1
        nextButton.isEnabled = false

        let round = currentRound
        let totalRounds = KanaPairMatchRoundBank.rounds.count
        progressLabel.text = "Round \(roundIndex + 1) of \(totalRounds)"
        updateInstruction(for: round)

        leftTileSpecs = shuffledTileSpecs(for: round, column: .left)
        rightTileSpecs = shuffledTileSpecs(for: round, column: .right)

        rebuildColumns(leftSpecs: leftTileSpecs, rightSpecs: rightTileSpecs)

        if animated {
            columnsStack.alpha = 0
            UIView.animate(withDuration: KanaPairMatchMotion.fadeInDuration, delay: 0, options: .curveEaseOut) {
                self.columnsStack.alpha = 1
            }
        } else {
            columnsStack.alpha = 1
        }
    }

    private func updateInstruction(for round: KanaPairMatchRound) {
        switch round.sideLayout {
        case .kanaOnLeft:
            instructionLabel.text = "Tap a kana tile, then its romaji match"
        case .romajiOnLeft:
            instructionLabel.text = "Tap a romaji tile, then its kana match"
        }
    }

    private func shuffledTileSpecs(
        for round: KanaPairMatchRound,
        column: KanaPairMatchTileSpec.Column
    ) -> [KanaPairMatchTileSpec] {
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

    private func rebuildColumns(
        leftSpecs: [KanaPairMatchTileSpec],
        rightSpecs: [KanaPairMatchTileSpec]
    ) {
        rebuildColumn(leftColumnStack, specs: leftSpecs)
        rebuildColumn(rightColumnStack, specs: rightSpecs)
    }

    private func rebuildColumn(
        _ stack: UIStackView,
        specs: [KanaPairMatchTileSpec]
    ) {
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
            checkRoundComplete()
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
        checkRoundComplete()
    }

    private func playPairMatchCascade(first: KanaPairMatchTileSpec, second: KanaPairMatchTileSpec) {
        pairMatchCascadeGeneration += 1
        let generation = pairMatchCascadeGeneration
        let specs = [first, second]
        let successSound = ExperimentFeedbackSound.prepareSuccess(for: .kanaSoundMatch)
        let chimeKeyTime = KanaSoundMatchMetrics.successChimeKeyTime
        let chimeLead = KanaPairMatchMotion.pairMatchChimeLead
        let stagger = KanaPairMatchMotion.successCascadeStagger

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
                    self.pronunciationPlayer.play(kana: kana)
                }

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                button.animateSuccessBounce(
                    successSound: playsChimeOnBounce ? successSound : nil,
                    successChimeKeyTime: playsChimeOnBounce ? chimeKeyTime : nil
                )
            }
        }
    }

    private func checkRoundComplete() {
        guard matchedPairIDs.count == currentRound.pairs.count else { return }
        instructionLabel.text = "Nice — all pairs matched"
        nextButton.isEnabled = true
    }

    @objc private func nextRoundTapped() {
        guard nextButton.isEnabled else { return }
        advanceRound()
    }

    private func advanceRound() {
        pairMatchCascadeGeneration += 1
        nextButton.isEnabled = false

        UIView.animate(
            withDuration: KanaPairMatchMotion.fadeOutDuration,
            delay: 0,
            options: .curveEaseIn
        ) { [weak self] in
            self?.columnsStack.alpha = 0
        } completion: { [weak self] _ in
            guard let self else { return }
            self.roundIndex = (self.roundIndex + 1) % KanaPairMatchRoundBank.rounds.count
            self.loadRound(animated: true)
        }
    }
}
