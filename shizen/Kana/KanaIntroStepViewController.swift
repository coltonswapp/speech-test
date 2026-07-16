//
//  KanaIntroStepViewController.swift
//  shizen
//
//  Presents a single kana glyph with romaji, audio, and mnemonic before drills.
//

import UIKit

final class KanaIntroStepViewController: LessonStepViewController {

    var onContinue: ((String) -> Void)?

    private let glyph: KanaGlyph
    private let pronunciationPlayer = KanaPronunciationPlayer()

    private let card = KanaCard()
    private let romajiLabel = UILabel()
    private let mnemonicLabel = UILabel()
    private let replayControl = LessonAudioReplayButton(size: 52, glyphPointSize: 22, glyphDimension: 26)

    private static let playButtonPressedFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.28, alpha: 1)
            : UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
    }

    init(glyph: KanaGlyph) {
        self.glyph = glyph
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ExperimentFeedbackSound.prepareClick()
        buildUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pronunciationPlayer.play(kana: glyph.kana)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pronunciationPlayer.stop()
    }

    private func buildUI() {
        card.setPresentation(.detailHero)
        card.configure(kana: glyph.kana, romaji: glyph.romaji)
        card.translatesAutoresizingMaskIntoConstraints = false

        romajiLabel.text = glyph.romaji
        romajiLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        romajiLabel.textAlignment = .center
        romajiLabel.textColor = .label

        let detail = KanaDetailCatalog.item(kana: glyph.kana, romaji: glyph.romaji)
        mnemonicLabel.text = detail.soundsLike
        mnemonicLabel.font = .preferredFont(forTextStyle: .body)
        mnemonicLabel.textColor = .secondaryLabel
        mnemonicLabel.textAlignment = .center
        mnemonicLabel.numberOfLines = 0

        configureInstruction("Tap to hear the sound.")
        configureReplayControl()
        configureCTA(.continue_(), target: self, action: #selector(continueTapped))

        let stack = makeLessonContentStack(
            belowInstruction: [card, romajiLabel, mnemonicLabel, replayControl],
            spacing: 16,
            afterInstructionSpacing: 20
        )
        stack.alignment = .center
        installLessonContent(stack, horizontalInset: 24)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 118),
        ])
    }

    private func configureReplayControl() {
        let button = replayControl.button
        button.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        button.addTarget(self, action: #selector(playButtonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(playButtonTouchUpInside), for: .touchUpInside)
        button.addTarget(self, action: #selector(playButtonTouchCancelled), for: .touchDragExit)
        button.addTarget(self, action: #selector(playButtonTouchCancelled), for: .touchUpOutside)
        button.addTarget(self, action: #selector(playButtonTouchCancelled), for: .touchCancel)
    }

    @objc private func playTapped() {
        pronunciationPlayer.play(kana: glyph.kana)
    }

    @objc private func playButtonTouchDown() {
        UIView.animate(withDuration: 0.12) {
            self.replayControl.button.backgroundColor = Self.playButtonPressedFill
        }
    }

    @objc private func playButtonTouchUpInside() {
        UIView.animate(withDuration: 0.12) {
            self.replayControl.button.backgroundColor = .clear
        }
    }

    @objc private func playButtonTouchCancelled() {
        UIView.animate(withDuration: 0.12) {
            self.replayControl.button.backgroundColor = .clear
        }
    }

    @objc private func continueTapped() {
        onContinue?(glyph.kana)
        advanceToNextStep()
    }
}
