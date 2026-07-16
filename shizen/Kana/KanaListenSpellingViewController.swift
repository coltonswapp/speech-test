//
//  KanaListenSpellingViewController.swift
//  shizen
//
//  Hear a word, then tap kana tiles to spell it.
//

import UIKit

/// Same tile spelling flow as ``KanaSpellingViewController``, but the target word is audio-only.
final class KanaListenSpellingViewController: KanaSpellingViewController {

    init(
        word: KanaSpellingWord,
        wordIndex: Int = 0,
        totalSteps: Int = KanaSpellingWordBank.words.count,
        script: KanaScript = .hiragana
    ) {
        super.init(
            word: word,
            wordIndex: wordIndex,
            totalSteps: totalSteps,
            promptStyle: .audio,
            script: script
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installCantListenRightNowButton(target: self, action: #selector(cantListenRightNowTapped))
    }

    @objc private func cantListenRightNowTapped() {
        progressiveContainerCoordinator?.removeListeningStepsFromLesson(from: self)
    }
}
