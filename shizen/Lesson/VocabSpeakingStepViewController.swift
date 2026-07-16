//
//  VocabSpeakingStepViewController.swift
//  shizen
//
//  DEBUG experiment: speak the target vocabulary word aloud to advance.
//

import Speech
import UIKit

// MARK: - State

private enum VocabSpeakingState {
    case idle
    case listening
    case matched
}

// MARK: - Step VC

final class VocabSpeakingStepViewController: ProgressiveStepViewController {

    // MARK: Data

    private let prompt: VocabSpeakingPrompt

    // MARK: Speech

    private let speechToText = JapaneseSpeechToText()
    private var currentState: VocabSpeakingState = .idle
    private var hasMatched = false
    private var advanceWorkItem: DispatchWorkItem?

    // MARK: UI

    private let contentStack = UIStackView()
    private let wordCard = UIView()
    private let hiraganaLabel = UILabel()
    private let romajiLabel = UILabel()
    private let instructionLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let micGlyphView = UIImageView()
    private let transcriptionLabel = UILabel()
    private let feedbackIcon = UIImageView()

    // MARK: Haptics

    private let tapHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()

    // MARK: Metrics & Colors

    private enum Metrics {
        static let micButtonSize: CGFloat = 96
        static let micGlyphSize: CGFloat = 40
        static let micBottomInset: CGFloat = 16
        static let transcriptionToMicSpacing: CGFloat = 12
        static let successAdvancePause: TimeInterval = 0.4
        static let cardRadius: CGFloat = 20
        static let cardPaddingH: CGFloat = 32
        static let cardPaddingV: CGFloat = 24
    }

    private enum Colors {
        static let green = UIColor(red: 0.35, green: 0.72, blue: 0.38, alpha: 1)
        static let greenBg = UIColor(red: 0.86, green: 0.95, blue: 0.86, alpha: 1)
    }

    // MARK: Init

    init(prompt: VocabSpeakingPrompt, stepIndex _: Int, totalSteps _: Int) {
        self.prompt = prompt
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.clipsToBounds = true
        configureLayout()
        transition(to: .idle, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        micButton.bringSubviewToFront(micGlyphView)
        view.bringSubviewToFront(transcriptionLabel)
        view.bringSubviewToFront(micButton)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        advanceWorkItem?.cancel()
        speechToText.stop()
    }

    // MARK: Layout

    private func configureLayout() {
        primaryButton.isHidden = true
        primaryButton.isUserInteractionEnabled = false
        primaryButton.isAccessibilityElement = false

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        instructionLabel.text = "Say this word aloud in Japanese."
        LessonInstructionLabel.apply(to: instructionLabel)

        hiraganaLabel.text = prompt.hiragana
        hiraganaLabel.font = .systemFont(ofSize: 52, weight: .bold)
        hiraganaLabel.textColor = .label
        hiraganaLabel.textAlignment = .center
        hiraganaLabel.adjustsFontSizeToFitWidth = true
        hiraganaLabel.minimumScaleFactor = 0.6

        romajiLabel.text = prompt.romaji
        romajiLabel.font = .systemFont(ofSize: 20, weight: .regular)
        romajiLabel.textColor = .secondaryLabel
        romajiLabel.textAlignment = .center
        let cardStack = UIStackView(arrangedSubviews: [hiraganaLabel, romajiLabel])
        cardStack.axis = .vertical
        cardStack.alignment = .center
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        wordCard.backgroundColor = .systemBackground
        wordCard.layer.cornerRadius = Metrics.cardRadius
        wordCard.layer.shadowColor = UIColor.black.cgColor
        wordCard.layer.shadowOpacity = 0.07
        wordCard.layer.shadowOffset = CGSize(width: 0, height: 2)
        wordCard.layer.shadowRadius = 8
        wordCard.layer.borderColor = UIColor(white: 0.88, alpha: 1).cgColor
        wordCard.layer.borderWidth = 1
        wordCard.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: wordCard.topAnchor, constant: Metrics.cardPaddingV),
            cardStack.bottomAnchor.constraint(equalTo: wordCard.bottomAnchor, constant: -Metrics.cardPaddingV),
            cardStack.leadingAnchor.constraint(equalTo: wordCard.leadingAnchor, constant: Metrics.cardPaddingH),
            cardStack.trailingAnchor.constraint(equalTo: wordCard.trailingAnchor, constant: -Metrics.cardPaddingH),
        ])

        configureMicButton()

        transcriptionLabel.numberOfLines = 2
        transcriptionLabel.textAlignment = .center
        transcriptionLabel.font = .preferredFont(forTextStyle: .footnote)
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        feedbackIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: symbolConfig)
        feedbackIcon.tintColor = Colors.green
        feedbackIcon.contentMode = .scaleAspectFit
        feedbackIcon.isHidden = true

        let feedbackContainer = UIView()
        feedbackContainer.translatesAutoresizingMaskIntoConstraints = false
        feedbackIcon.translatesAutoresizingMaskIntoConstraints = false
        feedbackContainer.addSubview(feedbackIcon)
        NSLayoutConstraint.activate([
            feedbackIcon.centerXAnchor.constraint(equalTo: feedbackContainer.centerXAnchor),
            feedbackIcon.topAnchor.constraint(equalTo: feedbackContainer.topAnchor),
            feedbackIcon.bottomAnchor.constraint(equalTo: feedbackContainer.bottomAnchor),
            feedbackIcon.heightAnchor.constraint(equalToConstant: 32),
        ])

        contentStack.addArrangedSubview(instructionLabel)
        contentStack.addArrangedSubview(wordCard)
        contentStack.addArrangedSubview(feedbackContainer)

        contentStack.setCustomSpacing(24, after: instructionLabel)

        contentView.addSubview(contentStack)
        view.addSubview(transcriptionLabel)
        view.addSubview(micButton)

        let contentInset: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: contentInset),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -contentInset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: transcriptionLabel.topAnchor, constant: -20),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Metrics.micBottomInset
            ),
            micButton.widthAnchor.constraint(equalToConstant: Metrics.micButtonSize),
            micButton.heightAnchor.constraint(equalToConstant: Metrics.micButtonSize),

            transcriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInset),
            transcriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInset),
            transcriptionLabel.bottomAnchor.constraint(
                equalTo: micButton.topAnchor,
                constant: -Metrics.transcriptionToMicSpacing
            ),
        ])
    }

    private func configureMicButton() {
        var micConfig = UIButton.Configuration.glass()
        micConfig.cornerStyle = .capsule
        micButton.configuration = micConfig
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.accessibilityLabel = "Record pronunciation"
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        micGlyphView.image = UIImage(systemName: "mic.fill", withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        micGlyphView.tintColor = .systemYellow
        micGlyphView.preferredSymbolConfiguration = symbolConfig
        micGlyphView.contentMode = .scaleAspectFit
        micGlyphView.isUserInteractionEnabled = false
        micGlyphView.translatesAutoresizingMaskIntoConstraints = false
        micButton.addSubview(micGlyphView)

        NSLayoutConstraint.activate([
            micGlyphView.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            micGlyphView.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            micGlyphView.widthAnchor.constraint(equalToConstant: Metrics.micGlyphSize),
            micGlyphView.heightAnchor.constraint(equalToConstant: Metrics.micGlyphSize),
        ])
    }

    // MARK: State transitions

    private func transition(to newState: VocabSpeakingState, animated: Bool) {
        currentState = newState
        switch newState {
        case .idle:
            hasMatched = false
            advanceWorkItem?.cancel()
            stopPulse()
            micButton.isEnabled = true
            transcriptionLabel.text = "Tap the mic to start"
            transcriptionLabel.textColor = .tertiaryLabel
            feedbackIcon.isHidden = true
            resetWordCardAppearance()

        case .listening:
            hasMatched = false
            advanceWorkItem?.cancel()
            micButton.isEnabled = true
            transcriptionLabel.text = "Listening…"
            transcriptionLabel.textColor = .secondaryLabel
            feedbackIcon.isHidden = true
            startPulse()

        case .matched:
            stopPulse()
            micButton.isEnabled = false
            transcriptionLabel.textColor = Colors.green
            feedbackIcon.isHidden = false
            if animated {
                successHaptic.notificationOccurred(.success)
                ExperimentFeedbackSound.playSuccess(for: .vocabSpeaking)
                animateMatchSuccess()
                scheduleAutoAdvanceAfterSuccess()
            }
        }
    }

    private func resetWordCardAppearance() {
        wordCard.backgroundColor = .systemBackground
        wordCard.layer.borderColor = UIColor(white: 0.88, alpha: 1).cgColor
        wordCard.layer.borderWidth = 1
    }

    private func scheduleAutoAdvanceAfterSuccess() {
        advanceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hasMatched else { return }
            self.progressiveContainerCoordinator?.advanceToNextStep(from: self)
        }
        advanceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.successAdvancePause, execute: work)
    }

    private func startPulse() {
        UIView.animate(
            withDuration: 0.7,
            delay: 0,
            options: [.repeat, .autoreverse, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.micButton.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        }
    }

    private func stopPulse() {
        micButton.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.15) {
            self.micButton.transform = .identity
        }
    }

    private func animateMatchSuccess() {
        UIView.animate(withDuration: 0.22) {
            self.wordCard.backgroundColor = Colors.greenBg
            self.wordCard.layer.borderColor = Colors.green.cgColor
            self.wordCard.layer.borderWidth = 2
        }

        feedbackIcon.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        feedbackIcon.alpha = 0
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.5
        ) {
            self.feedbackIcon.transform = .identity
            self.feedbackIcon.alpha = 1
        }
    }

    // MARK: Actions

    @objc private func micTapped() {
        tapHaptic.impactOccurred()
        switch currentState {
        case .idle:
            requestAuthAndStart()
        case .listening:
            speechToText.stop()
            transition(to: .idle, animated: true)
        case .matched:
            break
        }
    }

    // MARK: Speech recognition

    private func requestAuthAndStart() {
        Task {
            let status = await SpeechToTextAuthorization.request()
            await MainActor.run {
                switch status {
                case .authorized:
                    self.startListening()
                default:
                    self.showAuthDeniedAlert()
                }
            }
        }
    }

    private func startListening() {
        do {
            transition(to: .listening, animated: true)
            try speechToText.start(
                contextualStrings: prompt.contextualHints,
                onUpdate: { [weak self] text in self?.handleTranscription(text) },
                onError: { [weak self] _ in
                    guard let self, self.currentState == .listening, !self.hasMatched else { return }
                    self.transition(to: .idle, animated: true)
                }
            )
        } catch {
            transition(to: .idle, animated: true)
        }
    }

    private func handleTranscription(_ text: String) {
        guard currentState == .listening, !hasMatched else { return }

        if text.isEmpty {
            transcriptionLabel.text = "Listening…"
            transcriptionLabel.textColor = .secondaryLabel
        } else {
            transcriptionLabel.text = "\u{201C}\(text)\u{201D}"
            transcriptionLabel.textColor = .label
        }

        guard prompt.matches(transcription: text) else { return }

        hasMatched = true
        speechToText.stop()
        transcriptionLabel.text = "\u{201C}\(text)\u{201D}"
        transition(to: .matched, animated: true)
    }

    private func showAuthDeniedAlert() {
        let alert = UIAlertController(
            title: "Microphone Required",
            message: "Enable microphone and speech recognition in Settings to use this feature.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
