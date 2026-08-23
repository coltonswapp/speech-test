//
//  CompoundMeaningGameViewController.swift
//  shizen
//
//  DEBUG experiment: see 2 kanji → guess English meaning → closeness rank →
//  hint ladder → reveal (literal + stub dialogue). Throwaway-friendly POC.
//

import UIKit

final class CompoundMeaningGameViewController: UIViewController {

    // MARK: - State

    private var config: CompoundMeaningConfig
    private var puzzleIndex = 0
    private var guesses: [CompoundMeaningGuess] = []
    private var phase: CompoundMeaningPhase = .playing
    private var bestRank: Int?
    private var didShowCommitThisRound = false

    private var knobs: CompoundMeaningKnobs { config.knobs }
    private var puzzle: CompoundMeaningPuzzle {
        let puzzles = config.puzzles
        guard !puzzles.isEmpty else {
            return CompoundMeaningPuzzle(
                id: "empty",
                kanji: "??",
                reading: "",
                acceptedGlosses: [],
                components: [],
                literalBlurb: "No puzzles loaded.",
                dialogueLine: "",
                nearMissGlosses: [],
                rankHints: []
            )
        }
        return puzzles[puzzleIndex % puzzles.count]
    }

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let progressLabel = UILabel()
    private let promptLabel = UILabel()
    private let kanjiLabel = UILabel()
    private let triesLabel = UILabel()

    private let guessField = UITextField()
    private let guessButton = PrimaryButton()

    private let historyTitleLabel = UILabel()
    private let historyStack = UIStackView()

    private let hintsTitleLabel = UILabel()
    private let componentACard = UILabel()
    private let componentBCard = UILabel()

    private let commitCard = UIView()
    private let commitLabel = UILabel()
    private let continueAfterCommitButton = PrimaryButton()

    private let revealCard = UIView()
    private let revealTitleLabel = UILabel()
    private let revealBodyLabel = UILabel()
    private let dialogueLabel = UILabel()
    private let playAgainButton = PrimaryButton()

    private let statusLabel = UILabel()

    // MARK: - Init

    init(config: CompoundMeaningConfig = CompoundMeaningCatalog.load()) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compound meaning"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureNav()
        buildUI()
        loadRound(resetIndex: false)
        ExperimentFeedbackSound.prepareClick()
    }

    // MARK: - Nav / knobs

    private func configureNav() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(openKnobs)
        )
    }

    @objc private func openKnobs() {
        let sheet = CompoundMeaningKnobsViewController(knobs: knobs) { [weak self] updated in
            guard let self else { return }
            self.config.knobs = updated
            CompoundMeaningCatalog.saveKnobs(updated)
            self.refreshChrome()
        }
        let nav = UINavigationController(rootViewController: sheet)
        if let sheetController = nav.sheetPresentationController {
            sheetController.detents = [.medium(), .large()]
            sheetController.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - Build UI

    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        progressLabel.font = .preferredFont(forTextStyle: .caption1)
        progressLabel.textColor = .tertiaryLabel
        progressLabel.textAlignment = .center

        promptLabel.text = "Name the compound."
        promptLabel.font = .preferredFont(forTextStyle: .headline)
        promptLabel.textAlignment = .center
        promptLabel.textColor = .label

        kanjiLabel.font = .systemFont(ofSize: 64, weight: .medium)
        kanjiLabel.textAlignment = .center
        kanjiLabel.textColor = .label
        kanjiLabel.adjustsFontSizeToFitWidth = true
        kanjiLabel.minimumScaleFactor = 0.5

        triesLabel.font = .preferredFont(forTextStyle: .subheadline)
        triesLabel.textColor = .secondaryLabel
        triesLabel.textAlignment = .center

        guessField.placeholder = "English meaning"
        guessField.borderStyle = .roundedRect
        guessField.autocapitalizationType = .none
        guessField.autocorrectionType = .no
        guessField.returnKeyType = .go
        guessField.font = .preferredFont(forTextStyle: .body)
        guessField.delegate = self
        guessField.clearButtonMode = .whileEditing

        guessButton.primaryStyle = .blue
        guessButton.setTitle("Guess", for: .normal)
        guessButton.addTarget(self, action: #selector(submitGuess), for: .touchUpInside)

        historyTitleLabel.text = "Guesses"
        historyTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        historyTitleLabel.textColor = .secondaryLabel

        historyStack.axis = .vertical
        historyStack.spacing = 6

        hintsTitleLabel.text = "Hints"
        hintsTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintsTitleLabel.textColor = .secondaryLabel

        styleHintCard(componentACard)
        styleHintCard(componentBCard)

        styleSurfaceCard(commitCard)
        commitLabel.numberOfLines = 0
        commitLabel.textAlignment = .center
        commitLabel.font = .preferredFont(forTextStyle: .title2)
        commitLabel.translatesAutoresizingMaskIntoConstraints = false
        commitCard.addSubview(commitLabel)
        NSLayoutConstraint.activate([
            commitLabel.topAnchor.constraint(equalTo: commitCard.topAnchor, constant: 20),
            commitLabel.leadingAnchor.constraint(equalTo: commitCard.leadingAnchor, constant: 16),
            commitLabel.trailingAnchor.constraint(equalTo: commitCard.trailingAnchor, constant: -16),
            commitLabel.bottomAnchor.constraint(equalTo: commitCard.bottomAnchor, constant: -20),
        ])

        continueAfterCommitButton.primaryStyle = .yellow
        continueAfterCommitButton.setTitle("Keep guessing", for: .normal)
        continueAfterCommitButton.addTarget(self, action: #selector(dismissCommit), for: .touchUpInside)

        styleSurfaceCard(revealCard)
        revealTitleLabel.font = .preferredFont(forTextStyle: .title2)
        revealTitleLabel.textAlignment = .center
        revealTitleLabel.numberOfLines = 0

        revealBodyLabel.font = .preferredFont(forTextStyle: .body)
        revealBodyLabel.textColor = .secondaryLabel
        revealBodyLabel.numberOfLines = 0
        revealBodyLabel.textAlignment = .center

        dialogueLabel.font = .preferredFont(forTextStyle: .body)
        dialogueLabel.textColor = .label
        dialogueLabel.numberOfLines = 0
        dialogueLabel.textAlignment = .center

        let revealStack = UIStackView(arrangedSubviews: [revealTitleLabel, revealBodyLabel, dialogueLabel])
        revealStack.axis = .vertical
        revealStack.spacing = 10
        revealStack.translatesAutoresizingMaskIntoConstraints = false
        revealCard.addSubview(revealStack)
        NSLayoutConstraint.activate([
            revealStack.topAnchor.constraint(equalTo: revealCard.topAnchor, constant: 18),
            revealStack.leadingAnchor.constraint(equalTo: revealCard.leadingAnchor, constant: 16),
            revealStack.trailingAnchor.constraint(equalTo: revealCard.trailingAnchor, constant: -16),
            revealStack.bottomAnchor.constraint(equalTo: revealCard.bottomAnchor, constant: -18),
        ])

        playAgainButton.primaryStyle = .blue
        playAgainButton.setTitle("Play again", for: .normal)
        playAgainButton.addTarget(self, action: #selector(playAgain), for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        let boardCard = UIView()
        styleSurfaceCard(boardCard)
        let boardStack = UIStackView(arrangedSubviews: [promptLabel, kanjiLabel, triesLabel])
        boardStack.axis = .vertical
        boardStack.spacing = 8
        boardStack.translatesAutoresizingMaskIntoConstraints = false
        boardCard.addSubview(boardStack)
        NSLayoutConstraint.activate([
            boardStack.topAnchor.constraint(equalTo: boardCard.topAnchor, constant: 20),
            boardStack.leadingAnchor.constraint(equalTo: boardCard.leadingAnchor, constant: 16),
            boardStack.trailingAnchor.constraint(equalTo: boardCard.trailingAnchor, constant: -16),
            boardStack.bottomAnchor.constraint(equalTo: boardCard.bottomAnchor, constant: -20),
        ])

        [
            progressLabel,
            boardCard,
            guessField,
            guessButton,
            statusLabel,
            historyTitleLabel,
            historyStack,
            hintsTitleLabel,
            componentACard,
            componentBCard,
            commitCard,
            continueAfterCommitButton,
            revealCard,
            playAgainButton,
        ].forEach { contentStack.addArrangedSubview($0) }

        contentStack.setCustomSpacing(20, after: boardCard)
        contentStack.setCustomSpacing(8, after: guessField)
        contentStack.setCustomSpacing(18, after: guessButton)
        contentStack.setCustomSpacing(8, after: historyTitleLabel)
        contentStack.setCustomSpacing(8, after: hintsTitleLabel)
        contentStack.setCustomSpacing(18, after: componentBCard)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            guessButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            continueAfterCommitButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            playAgainButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(endEditingTap))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func styleSurfaceCard(_ view: UIView) {
        view.backgroundColor = ExperimentPalette.cardSurface
        view.layer.cornerRadius = 16
        view.layer.borderWidth = ExperimentCardStroke.normalWidth
        view.layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }

    private func styleHintCard(_ label: UILabel) {
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .label
        label.backgroundColor = ExperimentPalette.cardSurface
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.layer.borderWidth = ExperimentCardStroke.normalWidth
        label.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        label.textAlignment = .left
        // padding via attributed / insets hack — use text with leading spaces + layout margins via wrapper-ish padding
    }

    // MARK: - Round lifecycle

    private func loadRound(resetIndex: Bool) {
        if resetIndex {
            puzzleIndex = 0
        }
        guesses = []
        bestRank = nil
        phase = .playing
        didShowCommitThisRound = false
        guessField.text = ""
        guessField.isEnabled = true
        refreshAll()
        guessField.becomeFirstResponder()
    }

    private func refreshAll() {
        refreshChrome()
        rebuildHistory()
        refreshHints()
        refreshPhaseVisibility()
    }

    private func refreshChrome() {
        let total = max(config.puzzles.count, 1)
        progressLabel.text = "Puzzle \(puzzleIndex % total + 1) of \(total)"
        kanjiLabel.text = puzzle.kanji
        let remaining = max(0, knobs.maxGuesses - guesses.count)
        triesLabel.text = phase == .playing
            ? "\(remaining) guess\(remaining == 1 ? "" : "es") left · max \(knobs.maxGuesses)"
            : "Round over"
        statusLabel.text = knobs.audioPayoff
            ? "audioPayoff=true (TTS not wired in this POC)"
            : "Guess English · ranks are hand-authored"
    }

    private func rebuildHistory() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if guesses.isEmpty {
            let empty = UILabel()
            empty.text = "No guesses yet"
            empty.font = .preferredFont(forTextStyle: .footnote)
            empty.textColor = .tertiaryLabel
            historyStack.addArrangedSubview(empty)
            return
        }
        for guess in guesses.reversed() {
            historyStack.addArrangedSubview(makeHistoryRow(guess))
        }
    }

    private func makeHistoryRow(_ guess: CompoundMeaningGuess) -> UIView {
        let band = CompoundMeaningRanker.band(for: guess.rank, knobs: knobs)

        let row = UIView()
        row.backgroundColor = ExperimentPalette.cardSurface
        row.layer.cornerRadius = 10
        row.layer.borderWidth = 1
        row.layer.borderColor = band.color.withAlphaComponent(0.55).cgColor

        let badge = UILabel()
        badge.text = guess.isExact ? "1" : "\(guess.rank)"
        badge.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = band.color
        badge.layer.cornerRadius = 8
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let text = UILabel()
        text.text = guess.text
        text.font = .preferredFont(forTextStyle: .body)
        text.textColor = .label
        text.translatesAutoresizingMaskIntoConstraints = false

        let meta = UILabel()
        meta.text = band.name
        meta.font = .preferredFont(forTextStyle: .caption1)
        meta.textColor = band.color
        meta.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(badge)
        row.addSubview(text)
        row.addSubview(meta)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 36),
            badge.heightAnchor.constraint(equalToConstant: 28),

            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: meta.leadingAnchor, constant: -8),

            meta.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            meta.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return row
    }

    private func refreshHints() {
        let guessCount = guesses.count
        let showA = guessCount >= knobs.unlockComponentAAfterGuess || phaseRevealed
        let showB = guessCount >= knobs.unlockComponentBAfterGuess || phaseRevealed

        hintsTitleLabel.isHidden = !showA && !showB

        if showA, let a = puzzle.componentA {
            componentACard.isHidden = false
            componentACard.attributedText = hintAttributed(
                title: "Component A · \(a.char)",
                body: "\(a.gloss)\n\(a.readings.joined(separator: " · "))"
            )
        } else {
            componentACard.isHidden = true
            componentACard.text = nil
        }

        if showB, let b = puzzle.componentB {
            componentBCard.isHidden = false
            componentBCard.attributedText = hintAttributed(
                title: "Component B · \(b.char)",
                body: "\(b.gloss)\n\(b.readings.joined(separator: " · "))"
            )
        } else {
            componentBCard.isHidden = true
            componentBCard.text = nil
        }
    }

    private var phaseRevealed: Bool {
        if case .revealed = phase { return true }
        return false
    }

    private func hintAttributed(title: String, body: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: UIColor.label,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        result.append(NSAttributedString(string: "  \(title)\n", attributes: titleAttrs))
        result.append(NSAttributedString(string: "  \(body)\n ", attributes: bodyAttrs))
        return result
    }

    private func refreshPhaseVisibility() {
        switch phase {
        case .playing:
            guessField.isHidden = false
            guessButton.isHidden = false
            commitCard.isHidden = true
            continueAfterCommitButton.isHidden = true
            revealCard.isHidden = true
            playAgainButton.isHidden = true
            guessButton.isEnabled = guesses.count < knobs.maxGuesses

        case .commitInterstitial:
            guessField.isHidden = true
            guessButton.isHidden = true
            commitCard.isHidden = false
            continueAfterCommitButton.isHidden = false
            revealCard.isHidden = true
            playAgainButton.isHidden = true
            let a = puzzle.componentA?.char ?? "?"
            let b = puzzle.componentB?.char ?? "?"
            commitLabel.text = "\(a) + \(b)  →  ?"

        case .revealed(let won):
            guessField.isHidden = true
            guessButton.isHidden = true
            commitCard.isHidden = true
            continueAfterCommitButton.isHidden = true
            revealCard.isHidden = false
            playAgainButton.isHidden = false
            populateReveal(won: won)
        }
    }

    private func populateReveal(won: Bool) {
        let gloss = puzzle.primaryGloss
        revealTitleLabel.text = "\(puzzle.kanji) · \(puzzle.reading)\n\(gloss)"
        revealTitleLabel.textColor = won ? ExperimentPalette.successBorder : .label

        if won {
            revealBodyLabel.text = puzzle.literalBlurb
        } else {
            let best = bestRank.map(String.init) ?? "—"
            revealBodyLabel.text = "Out of guesses. Best rank: \(best)\n\n\(puzzle.literalBlurb)"
        }
        dialogueLabel.text = "“\(puzzle.dialogueLine)”"

        if knobs.audioPayoff {
            // Stub only — no TTS wiring in this POC.
            statusLabel.text = "audioPayoff stub: would speak “\(puzzle.dialogueLine)”"
        }
    }

    // MARK: - Actions

    @objc private func endEditingTap() {
        view.endEditing(true)
    }

    @objc private func submitGuess() {
        guard phase == .playing else { return }
        guard guesses.count < knobs.maxGuesses else {
            reveal(won: false)
            return
        }

        let raw = guessField.text ?? ""
        let normalized = CompoundMeaningRanker.normalize(raw)
        guard !normalized.isEmpty else {
            statusLabel.text = "Type an English meaning first"
            return
        }

        // Avoid duplicate guesses (same normalized form).
        if guesses.contains(where: { CompoundMeaningRanker.normalize($0.text) == normalized }) {
            statusLabel.text = "Already guessed that"
            return
        }

        let result = CompoundMeaningRanker.rank(guess: raw, in: puzzle)
        guesses.append(result)
        bestRank = min(bestRank ?? result.rank, result.rank)
        guessField.text = ""
        ExperimentFeedbackSound.playClick()

        if result.isExact {
            ExperimentFeedbackSound.playSuccess(for: .kanaSoundMatch)
            reveal(won: true)
            return
        }

        ExperimentFeedbackSound.playIncorrect()
        refreshAll()

        if guesses.count >= knobs.maxGuesses {
            reveal(won: false)
            return
        }

        maybeShowCommitInterstitial()
    }

    private func maybeShowCommitInterstitial() {
        guard knobs.showCommitInterstitial else { return }
        guard !didShowCommitThisRound else { return }
        guard guesses.count >= knobs.commitAfterGuess else { return }
        didShowCommitThisRound = true
        phase = .commitInterstitial
        view.endEditing(true)
        refreshPhaseVisibility()
    }

    @objc private func dismissCommit() {
        phase = .playing
        refreshPhaseVisibility()
        guessField.becomeFirstResponder()
    }

    private func reveal(won: Bool) {
        phase = .revealed(won: won)
        view.endEditing(true)
        refreshAll()
        if won {
            // success sound already played on exact hit
        }
    }

    @objc private func playAgain() {
        guard !config.puzzles.isEmpty else { return }
        puzzleIndex = (puzzleIndex + 1) % config.puzzles.count
        guesses = []
        bestRank = nil
        phase = .playing
        didShowCommitThisRound = false
        guessField.text = ""
        refreshAll()
        guessField.becomeFirstResponder()
    }
}

// MARK: - UITextFieldDelegate

extension CompoundMeaningGameViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitGuess()
        return true
    }
}

// MARK: - Knobs sheet

final class CompoundMeaningKnobsViewController: UITableViewController {

    private var knobs: CompoundMeaningKnobs
    private let onSave: (CompoundMeaningKnobs) -> Void

    init(knobs: CompoundMeaningKnobs, onSave: @escaping (CompoundMeaningKnobs) -> Void) {
        self.knobs = knobs
        self.onSave = onSave
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private enum Row: Int, CaseIterable {
        case maxGuesses
        case unlockA
        case unlockB
        case showCommit
        case commitAfter
        case audioPayoff
        case reset
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Knobs"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Apply",
            style: .done,
            target: self,
            action: #selector(apply)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func apply() {
        onSave(knobs)
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? Row.allCases.count - 1 : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Session knobs (persisted)" : "Bundle"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? "colorBands live in CompoundMeaningPuzzles.json — edit JSON to retune rank colors."
            : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.contentConfiguration = nil

        if indexPath.section == 1 {
            var config = cell.defaultContentConfiguration()
            config.text = "Reset knobs to JSON defaults"
            config.textProperties.color = .systemRed
            cell.contentConfiguration = config
            cell.selectionStyle = .default
            return cell
        }

        guard let row = Row(rawValue: indexPath.row) else { return cell }

        switch row {
        case .maxGuesses:
            configureStepperCell(cell, title: "maxGuesses", value: knobs.maxGuesses, min: 1, max: 12) { [weak self] v in
                self?.knobs.maxGuesses = v
            }
        case .unlockA:
            configureStepperCell(cell, title: "unlockComponentAAfterGuess", value: knobs.unlockComponentAAfterGuess, min: 0, max: 12) { [weak self] v in
                self?.knobs.unlockComponentAAfterGuess = v
            }
        case .unlockB:
            configureStepperCell(cell, title: "unlockComponentBAfterGuess", value: knobs.unlockComponentBAfterGuess, min: 0, max: 12) { [weak self] v in
                self?.knobs.unlockComponentBAfterGuess = v
            }
        case .showCommit:
            configureSwitchCell(cell, title: "showCommitInterstitial", isOn: knobs.showCommitInterstitial) { [weak self] on in
                self?.knobs.showCommitInterstitial = on
            }
        case .commitAfter:
            configureStepperCell(cell, title: "commitAfterGuess", value: knobs.commitAfterGuess, min: 1, max: 12) { [weak self] v in
                self?.knobs.commitAfterGuess = v
            }
        case .audioPayoff:
            configureSwitchCell(cell, title: "audioPayoff (stub)", isOn: knobs.audioPayoff) { [weak self] on in
                self?.knobs.audioPayoff = on
            }
        case .reset:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        CompoundMeaningCatalog.resetKnobsToBundleDefaults()
        let reloaded = CompoundMeaningCatalog.load()
        knobs = reloaded.knobs
        onSave(knobs)
        tableView.reloadData()
    }

    private func configureStepperCell(
        _ cell: UITableViewCell,
        title: String,
        value: Int,
        min: Double,
        max: Double,
        onChange: @escaping (Int) -> Void
    ) {
        var config = cell.defaultContentConfiguration()
        config.text = title
        config.secondaryText = "\(value)"
        cell.contentConfiguration = config

        let stepper = UIStepper()
        stepper.minimumValue = min
        stepper.maximumValue = max
        stepper.stepValue = 1
        stepper.value = Double(value)
        stepper.addAction(UIAction { [weak cell] action in
            guard let stepper = action.sender as? UIStepper else { return }
            let v = Int(stepper.value)
            onChange(v)
            var updated = cell?.defaultContentConfiguration() ?? UIListContentConfiguration.subtitleCell()
            updated.text = title
            updated.secondaryText = "\(v)"
            cell?.contentConfiguration = updated
        }, for: .valueChanged)
        cell.accessoryView = stepper
    }

    private func configureSwitchCell(
        _ cell: UITableViewCell,
        title: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) {
        var config = cell.defaultContentConfiguration()
        config.text = title
        cell.contentConfiguration = config
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addAction(UIAction { action in
            guard let toggle = action.sender as? UISwitch else { return }
            onChange(toggle.isOn)
        }, for: .valueChanged)
        cell.accessoryView = toggle
    }
}
