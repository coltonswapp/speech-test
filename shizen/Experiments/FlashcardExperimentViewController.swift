//
//  FlashcardExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: swipeable vocab flashcards (right = know, left = review).
//

import InteractionKit
import UIKit

final class FlashcardExperimentViewController: UIViewController {

    private let stackView = FlashcardStackView()
    private let instructionsLabel = UILabel()

    private var knownIndices: Set<Int> = []
    private var reviewIndices: Set<Int> = []
    private var furiganaToggleButton: UIBarButtonItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Flashcards"
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItems()
        view.backgroundColor = ExperimentPalette.pageBackground

        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionsLabel.text = "Swipe right if you know it · left to review again · tap to reveal"
        instructionsLabel.font = .preferredFont(forTextStyle: .footnote)
        instructionsLabel.textColor = .tertiaryLabel
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.delegate = self

        view.addSubview(stackView)
        view.addSubview(instructionsLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: instructionsLabel.topAnchor, constant: -16),

            instructionsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            instructionsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        stackView.setDeck(VocabFlashcardBank.starter)
    }

    private func configureNavigationItems() {
        let furiganaToggle = UIBarButtonItem(
            title: "あ",
            style: .plain,
            target: self,
            action: #selector(toggleFuriganaTapped)
        )
        furiganaToggleButton = furiganaToggle
        updateFuriganaToggleAppearance()
        navigationItem.rightBarButtonItem = furiganaToggle
    }

    @objc private func toggleFuriganaTapped() {
        JapaneseFuriganaSettings.showOnFlashcards.toggle()
        updateFuriganaToggleAppearance()
        stackView.refreshFuriganaDisplay()
    }

    private func updateFuriganaToggleAppearance() {
        let on = JapaneseFuriganaSettings.showOnFlashcards
        furiganaToggleButton?.title = on ? "あ" : "文"
        furiganaToggleButton?.tintColor = on ? view.tintColor : .secondaryLabel
    }
}

extension FlashcardExperimentViewController: FlashcardStackViewDelegate {
    func flashcardStack(_ stack: FlashcardStackView, didTapCardAt index: Int) {}

    func flashcardStack(_ stack: FlashcardStackView, didSwipeCardAt index: Int, direction: FlashcardSwipeDirection) {
        switch direction {
        case .right: knownIndices.insert(index)
        case .left: reviewIndices.insert(index)
        }
    }

    func flashcardStackDidFinish(_ stack: FlashcardStackView) {
        let known = knownIndices.count
        let review = reviewIndices.count
        instructionsLabel.text = "Known: \(known) · Review: \(review)"
    }
}
