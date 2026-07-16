//
//  TextToSpeechExperimentViewController.swift
//  shizen
//
//  Debug experiment: Input → Actions → Sentences (streamed OpenAI TTS).
//

import UIKit
import TTSCore

private enum TTSSection: Int, CaseIterable {
    case input = 0
    case actions = 1
    case chunks = 2

    var title: String {
        switch self {
        case .input: return "Input"
        case .actions: return "Actions"
        case .chunks: return "Sentences"
        }
    }

    var showsFooter: Bool {
        self == .chunks
    }

    var footerText: String? {
        switch self {
        case .chunks:
            return """
            Speak uses one streamed TTS request for the full text. Each row is a sentence aligned into that single recording (not its own API call). Audio plays as it arrives; tap a row to replay just that slice.
            """
        case .input, .actions:
            return nil
        }
    }
}

final class TextToSpeechExperimentViewController: UIViewController {

    private let tts = TextToSpeechService(apiKey: OpenAIAppKey.resolved)

    private var collectionView: UICollectionView!

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var footerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var inputCellRegistration: UICollectionView.CellRegistration<TTSInputCollectionViewCell, Void>!
    private var actionsCellRegistration: UICollectionView.CellRegistration<TTSActionsCollectionViewCell, Void>!
    private var toolbarCellRegistration: UICollectionView.CellRegistration<TTSChunkToolbarCollectionViewCell, Void>!
    private var sentenceCellRegistration: UICollectionView.CellRegistration<ChunkCollectionViewCell, Int>!

    private var inputBody: String = """
    いらっしゃいませ！
    アイスクリームですね。ありがとうございます。少々お待ちください。
    全部で二百円です。
    ありがとうございます。お釣りは三百円です。どうぞ。
    袋はいりますか？
    では、ありがとうございました！またお越しくださいませ！
    """

    private var selectedVoice: OpenAITTSVoice = .coral
    private var currentlyPlayingSentenceIndex: Int?
    private var idleFadeTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Text to Speech"
        tts.delegate = self

        headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { supplementaryView, _, indexPath in
            guard let section = TTSSection(rawValue: indexPath.section) else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            configuration.text = section.title.uppercased()
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { supplementaryView, _, indexPath in
            guard let section = TTSSection(rawValue: indexPath.section),
                  let text = section.footerText
            else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            configuration.text = text
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
            configuration.textProperties.color = .secondaryLabel
            configuration.textProperties.alignment = .natural
            configuration.textProperties.numberOfLines = 0
            supplementaryView.contentConfiguration = configuration
        }

        inputCellRegistration = UICollectionView.CellRegistration<TTSInputCollectionViewCell, Void> {
            [weak self] cell, _, _ in
            self?.configureInputCell(cell)
        }

        actionsCellRegistration = UICollectionView.CellRegistration<TTSActionsCollectionViewCell, Void> {
            [weak self] cell, _, _ in
            self?.wireActionsCell(cell)
        }

        toolbarCellRegistration = UICollectionView.CellRegistration<TTSChunkToolbarCollectionViewCell, Void> {
            [weak self] cell, _, _ in
            self?.configureSentenceToolbarCell(cell)
        }

        sentenceCellRegistration = UICollectionView.CellRegistration<ChunkCollectionViewCell, Int> {
            [weak self] cell, _, sentenceIndex in
            self?.configureSentenceCell(cell, sentenceIndex: sentenceIndex)
        }

        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment in
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            listConfiguration.headerMode = .supplementary
            if let section = TTSSection(rawValue: sectionIndex) {
                listConfiguration.footerMode = section.showsFooter ? .supplementary : .none
            } else {
                listConfiguration.footerMode = .none
            }
            listConfiguration.showsSeparators = false
            return NSCollectionLayoutSection.list(
                using: listConfiguration,
                layoutEnvironment: layoutEnvironment
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInset.bottom = 16
        collectionView.dataSource = self
        collectionView.delegate = self

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reloadAllSections()
        updateForState(tts.state)
    }

    func importSavedGeneration(from directory: URL) throws {
        collectionView.endEditing(true)
        try tts.loadSavedBundle(at: directory)
    }

    // MARK: - Reload

    private func reloadAllSections() {
        collectionView.reloadData()
    }

    private func reloadSentencesSection() {
        collectionView.reloadSections(IndexSet(integer: TTSSection.chunks.rawValue))
    }

    private func reloadActionsSection() {
        collectionView.reloadSections(IndexSet(integer: TTSSection.actions.rawValue))
    }

    private func configureInputCell(_ cell: TTSInputCollectionViewCell) {
        if cell.textView.text != inputBody {
            cell.textView.text = inputBody
        }
        cell.textView.delegate = self
    }

    private func wireActionsCell(_ cell: TTSActionsCollectionViewCell) {
        cell.voiceButton.showsMenuAsPrimaryAction = true
        cell.voiceButton.menu = makeVoiceMenu()

        cell.speakButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.speakButton.addAction(UIAction { [weak self] _ in self?.speakTapped() }, for: .primaryActionTriggered)

        cell.stopButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.stopButton.addAction(UIAction { [weak self] _ in self?.stopTapped() }, for: .primaryActionTriggered)

        cell.playPauseButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.playPauseButton.addAction(UIAction { [weak self] _ in self?.playPauseTapped() }, for: .primaryActionTriggered)

        refreshVoiceButtonTitle(in: cell)
        syncActionsCellState(cell)
    }

    private func configureSentenceToolbarCell(_ cell: TTSChunkToolbarCollectionViewCell) {
        cell.replayAllButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.replayAllButton.addAction(UIAction { [weak self] _ in self?.replayAllTapped() }, for: .primaryActionTriggered)
        cell.lyricsButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.lyricsButton.addAction(UIAction { [weak self] _ in self?.lyricsTapped() }, for: .primaryActionTriggered)
        cell.saveButton.removeTarget(nil, action: nil, for: .primaryActionTriggered)
        cell.saveButton.addAction(UIAction { [weak self] _ in self?.saveTapped() }, for: .primaryActionTriggered)
        let sentences = tts.sentences
        let n = sentences.count
        if n == 0 {
            cell.summaryLabel.text = """
            No audio yet. Enter text in Input, then tap Speak. One synthesis covers the whole passage; each row maps to a sentence slice in that audio. Tap Save to store audio and timing offline. Tap a row to replay that sentence.
            """
        } else {
            let readyCount = sentences.filter {
                if case .ready = $0.state { return true }
                return false
            }.count
            cell.summaryLabel.text = String(
                format: "%d sentence%@ · %d ready · %.2fs audio",
                n,
                n == 1 ? "" : "s",
                readyCount,
                tts.totalDuration
            )
        }
        let hasPlayable = sentences.contains(where: {
            if case .ready = $0.state { return $0.sampleCount > 0 }
            return false
        })
        cell.replayAllButton.isEnabled = hasPlayable
        cell.lyricsButton.isEnabled = !sentences.isEmpty
        cell.saveButton.isEnabled = tts.canExportSavedSnapshot
    }

    private func configureSentenceCell(_ cell: ChunkCollectionViewCell, sentenceIndex: Int) {
        guard tts.sentences.indices.contains(sentenceIndex) else { return }
        let s = tts.sentences[sentenceIndex]
        let playing = (currentlyPlayingSentenceIndex == sentenceIndex) && tts.state == .playing
        cell.apply(
            sentence: s,
            isPlaying: playing,
            trait: collectionView.traitCollection
        )
        cell.onPlay = { [weak self] in
            self?.togglePlay(forSentenceAt: sentenceIndex)
        }
    }

    private func actionsCellIfLoaded() -> TTSActionsCollectionViewCell? {
        let path = IndexPath(item: 0, section: TTSSection.actions.rawValue)
        return collectionView.cellForItem(at: path) as? TTSActionsCollectionViewCell
    }

    // MARK: - Voice

    private func makeVoiceMenu() -> UIMenu {
        let actions: [UIAction] = OpenAITTSVoice.allCases.map { voice in
            UIAction(
                title: voice.rawValue,
                state: voice == selectedVoice ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.selectedVoice = voice
                if let ac = self.actionsCellIfLoaded() {
                    self.refreshVoiceButtonTitle(in: ac)
                }
                self.actionsCellIfLoaded()?.voiceButton.menu = self.makeVoiceMenu()
            }
        }
        return UIMenu(title: "Choose a voice", children: actions)
    }

    private func refreshVoiceButtonTitle(in cell: TTSActionsCollectionViewCell) {
        var cfg = cell.voiceButton.configuration ?? .bordered()
        cfg.title = "Voice: \(selectedVoice.rawValue)"
        cfg.image = UIImage(systemName: "chevron.down")
        cfg.imagePlacement = .trailing
        cfg.imagePadding = 6
        cell.voiceButton.configuration = cfg
    }

    // MARK: - Actions

    private func speakTapped() {
        let text = inputBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            presentMessage(
                title: "No text to speak",
                message: "Enter text in Input, then tap Speak."
            )
            return
        }
        view.endEditing(true)
        currentlyPlayingSentenceIndex = nil
        startIdleFade(false)
        tts.speak(text: text, voice: selectedVoice) { error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.presentMessage(title: "Text to Speech error", message: message)
            }
        }
    }

    private func stopTapped() {
        tts.stop()
        currentlyPlayingSentenceIndex = nil
        refreshVisibleSentenceCells()
    }

    private func replayAllTapped() {
        guard !tts.sentences.isEmpty else { return }
        currentlyPlayingSentenceIndex = nil
        refreshVisibleSentenceCells()
        tts.replayAll()
    }

    private func lyricsTapped() {
        guard !tts.sentences.isEmpty else { return }
        let lyrics = LyricsViewController(service: tts)
        let nav = UINavigationController(rootViewController: lyrics)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true) { [weak self] in
            guard let self else { return }
            if self.tts.state == .readyForReplay {
                self.tts.replayAll()
            }
        }
    }

    private func saveTapped() {
        guard tts.canExportSavedSnapshot else { return }
        do {
            let dir = try SavedGenerationStore.shared.makeNewBundleDirectory()
            try tts.exportSavedBundle(to: dir)
            presentMessage(
                title: "Saved",
                message: "Open the gear menu to browse saved generations."
            )
        } catch {
            presentError(error)
        }
    }

    private func playPauseTapped() {
        switch tts.state {
        case .playing:
            tts.pause()
        case .paused:
            tts.resume()
        case .readyForReplay:
            tts.replayAll()
        case .idle, .streaming:
            break
        }
    }

    // MARK: - State → UI

    private func updateForState(_ state: TTSPlaybackState) {
        if let cell = actionsCellIfLoaded() {
            syncActionsCellState(cell)
        } else {
            reloadActionsSection()
        }

        if let toolbarCell = collectionView.cellForItem(at: IndexPath(item: 0, section: TTSSection.chunks.rawValue))
            as? TTSChunkToolbarCollectionViewCell
        {
            configureSentenceToolbarCell(toolbarCell)
        }

        switch state {
        case .idle:
            startIdleFade(true)
        case .streaming:
            startIdleFade(false)
        case .readyForReplay, .paused:
            startIdleFade(true)
        case .playing:
            startIdleFade(false)
        }

        if state != .playing {
            currentlyPlayingSentenceIndex = nil
        }
        refreshVisibleSentenceCells()
    }

    private func syncActionsCellState(_ cell: TTSActionsCollectionViewCell) {
        let state = tts.state
        let sentenceCount = tts.sentences.count
        let readyCount = tts.sentences.filter {
            if case .ready = $0.state { return true }
            return false
        }.count
        switch state {
        case .idle:
            cell.statusLabel.text = "Idle"
            setSpeakSpeaking(false, cell: cell)
            setPlayPause(isPlaying: false, enabled: false, cell: cell)
            cell.stopButton.isEnabled = false
        case .streaming:
            cell.statusLabel.text = String(
                format: "Streaming · %d / %d sentence%@ ready",
                readyCount,
                sentenceCount,
                sentenceCount == 1 ? "" : "s"
            )
            setSpeakSpeaking(true, cell: cell)
            setPlayPause(isPlaying: true, enabled: false, cell: cell)
            cell.stopButton.isEnabled = true
        case .readyForReplay:
            cell.statusLabel.text = String(
                format: "Ready · %d sentence%@ · %.2fs",
                sentenceCount,
                sentenceCount == 1 ? "" : "s",
                tts.totalDuration
            )
            setSpeakSpeaking(false, cell: cell)
            setPlayPause(isPlaying: false, enabled: true, cell: cell)
            cell.stopButton.isEnabled = false
        case .playing:
            cell.statusLabel.text = "Playing"
            setSpeakSpeaking(false, cell: cell)
            setPlayPause(isPlaying: true, enabled: true, cell: cell)
            cell.stopButton.isEnabled = true
        case .paused:
            cell.statusLabel.text = "Paused"
            setSpeakSpeaking(false, cell: cell)
            setPlayPause(isPlaying: false, enabled: true, cell: cell)
            cell.stopButton.isEnabled = true
        }
    }

    private func setSpeakSpeaking(_ speaking: Bool, cell: TTSActionsCollectionViewCell) {
        var cfg = cell.speakButton.configuration ?? .borderedProminent()
        cfg.title = speaking ? "Streaming…" : "Speak"
        cfg.showsActivityIndicator = speaking
        cell.speakButton.configuration = cfg
        cell.speakButton.isEnabled = !speaking
    }

    private func setPlayPause(isPlaying: Bool, enabled: Bool, cell: TTSActionsCollectionViewCell) {
        var cfg = cell.playPauseButton.configuration ?? .tinted()
        cfg.image = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill")
        cfg.title = isPlaying ? "Pause" : "Play"
        cell.playPauseButton.configuration = cfg
        cell.playPauseButton.isEnabled = enabled
    }

    private func refreshVisibleSentenceCells() {
        let chunkSection = TTSSection.chunks.rawValue
        let n = collectionView.numberOfItems(inSection: chunkSection)
        if n != 1 + tts.sentences.count {
            reloadSentencesSection()
            return
        }
        for row in 0..<n {
            let path = IndexPath(item: row, section: chunkSection)
            if let cell = collectionView.cellForItem(at: path) as? ChunkCollectionViewCell {
                let idx = path.item - 1
                configureSentenceCell(cell, sentenceIndex: idx)
            } else if let tcell = collectionView.cellForItem(at: path) as? TTSChunkToolbarCollectionViewCell {
                configureSentenceToolbarCell(tcell)
            }
        }
    }

    private func startIdleFade(_ enabled: Bool) {
        idleFadeTimer?.invalidate()
        idleFadeTimer = nil
        guard enabled else { return }
        idleFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.actionsCellIfLoaded()?.waveform.fadeToZero()
        }
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        presentMessage(title: "Text to Speech error", message: error.localizedDescription)
    }

    private func togglePlay(forSentenceAt index: Int) {
        guard tts.sentences.indices.contains(index) else { return }
        let s = tts.sentences[index]
        if case .ready = s.state {} else { return }

        if currentlyPlayingSentenceIndex == index, tts.state == .playing {
            tts.stop()
            currentlyPlayingSentenceIndex = nil
            refreshVisibleSentenceCells()
            return
        }
        currentlyPlayingSentenceIndex = index
        refreshVisibleSentenceCells()
        tts.play(sentenceAt: index)
    }
}

// MARK: - UITextViewDelegate

extension TextToSpeechExperimentViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        inputBody = textView.text ?? ""
    }
}

// MARK: - UICollectionViewDataSource

extension TextToSpeechExperimentViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        TTSSection.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sec = TTSSection(rawValue: section) else { return 0 }
        switch sec {
        case .input:
            return 1
        case .actions:
            return 1
        case .chunks:
            return 1 + tts.sentences.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let sec = TTSSection(rawValue: indexPath.section) else {
            return UICollectionViewCell()
        }
        switch sec {
        case .input:
            return collectionView.dequeueConfiguredReusableCell(using: inputCellRegistration, for: indexPath, item: ())
        case .actions:
            return collectionView.dequeueConfiguredReusableCell(using: actionsCellRegistration, for: indexPath, item: ())
        case .chunks:
            if indexPath.item == 0 {
                return collectionView.dequeueConfiguredReusableCell(using: toolbarCellRegistration, for: indexPath, item: ())
            }
            let sentenceIndex = indexPath.item - 1
            return collectionView.dequeueConfiguredReusableCell(using: sentenceCellRegistration, for: indexPath, item: sentenceIndex)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionHeader:
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        case UICollectionView.elementKindSectionFooter:
            return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
        default:
            preconditionFailure("unexpected supplementary kind \(kind)")
        }
    }
}

// MARK: - TextToSpeechServiceDelegate

extension TextToSpeechExperimentViewController: TextToSpeechServiceDelegate {

    func textToSpeechService(_ service: TextToSpeechService, didStartStreamingFor text: String) {
        reloadSentencesSection()
        if let ac = actionsCellIfLoaded() {
            syncActionsCellState(ac)
        }
    }

    func textToSpeechService(_ service: TextToSpeechService, didUpdateSentenceAt index: Int) {
        let chunkSection = TTSSection.chunks.rawValue
        let expected = 1 + service.sentences.count
        if collectionView.numberOfItems(inSection: chunkSection) != expected {
            reloadSentencesSection()
        } else {
            let path = IndexPath(item: index + 1, section: chunkSection)
            if let cell = collectionView.cellForItem(at: path) as? ChunkCollectionViewCell {
                configureSentenceCell(cell, sentenceIndex: index)
            }
            if let tcell = collectionView.cellForItem(at: IndexPath(item: 0, section: chunkSection))
                as? TTSChunkToolbarCollectionViewCell
            {
                configureSentenceToolbarCell(tcell)
            }
        }
        if let ac = actionsCellIfLoaded() {
            syncActionsCellState(ac)
        }
    }

    func textToSpeechService(_ service: TextToSpeechService, didChangeState state: TTSPlaybackState) {
        updateForState(state)
    }

    func textToSpeechService(_ service: TextToSpeechService, didUpdateLevel level: Float) {
        actionsCellIfLoaded()?.waveform.append(level: level)
    }

    func textToSpeechService(_ service: TextToSpeechService, didFailWith error: Error) {
        presentError(error)
    }

    func textToSpeechServiceDidRestoreSavedUtterance(_ service: TextToSpeechService) {
        selectedVoice = service.lastSynthesisVoice
        currentlyPlayingSentenceIndex = nil
        idleFadeTimer?.invalidate()
        idleFadeTimer = nil
        inputBody = service.utteranceSourceText
        reloadAllSections()
        updateForState(service.state)
        if let ac = actionsCellIfLoaded() {
            refreshVoiceButtonTitle(in: ac)
            ac.voiceButton.menu = makeVoiceMenu()
        }
    }

    func textToSpeechServiceDidFinish(_ service: TextToSpeechService) {
        print("═══ TTS utterance finished ═══")
        print("  text: \"\(service.utteranceSourceText)\"")
        print(String(format: "  totalAudio: %.2fs", service.totalDuration))
        for (i, s) in service.sentences.enumerated() {
            let state: String
            switch s.state {
            case .pending: state = "pending"
            case .streaming: state = "streaming"
            case .ready: state = "ready"
            case .failed(let m): state = "failed(\(m))"
            }
            print(String(format: "  sentence %d [%@] %.2fs: \"%@\"", i + 1, state, s.duration, s.text))
        }
        print("══════════════════════════════")

        refreshVisibleSentenceCells()
        if let ac = actionsCellIfLoaded() {
            syncActionsCellState(ac)
        }
    }
}

// MARK: - UICollectionViewDelegate

extension TextToSpeechExperimentViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard indexPath.section == TTSSection.chunks.rawValue, indexPath.item >= 1 else { return false }
        let idx = indexPath.item - 1
        guard tts.sentences.indices.contains(idx) else { return false }
        if case .ready = tts.sentences[idx].state { return true }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.section == TTSSection.chunks.rawValue, indexPath.item > 0 else { return }
        let idx = indexPath.item - 1
        togglePlay(forSentenceAt: idx)
    }
}
