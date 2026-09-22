//
//  RegisterLadderPagerViewController.swift
//  shizen
//
//  Slideshow for one English idea said three ways (casual / polite / keigo),
//  then a why close. Swiping, export, and hashtags live on
//  ExperimentSlideshowViewController. Japanese on register slides is tap-to-edit.
//

import UIKit

final class RegisterLadderPagerViewController: ExperimentSlideshowViewController {

    private let deck: RegisterLadderDeck
    private var japaneseTapGesture: UITapGestureRecognizer?

    override var recommendedHashtags: [String] { ExperimentHashtags.registerLadder }

    init(deck: RegisterLadderDeck) {
        self.deck = deck
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = "Register ladder"
        super.viewDidLoad()
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        [
            ExperimentSlidePageViewController {
                let cardView = RegisterLadderHookCardView()
                cardView.configure(english: self.deck.english)
                return cardView
            },
            ExperimentSlidePageViewController {
                let cardView = RegisterLadderLevelCardView(register: .casual)
                cardView.configure(level: self.deck.casual)
                return cardView
            },
            ExperimentSlidePageViewController {
                let cardView = RegisterLadderLevelCardView(register: .polite)
                cardView.configure(level: self.deck.polite)
                return cardView
            },
            ExperimentSlidePageViewController {
                let cardView = RegisterLadderLevelCardView(register: .formal)
                cardView.configure(level: self.deck.formal)
                return cardView
            },
            ExperimentSlidePageViewController {
                let cardView = RegisterLadderWhyCardView()
                cardView.configure(why: self.deck.why)
                return cardView
            },
        ]
    }

    override func slideshowDidShowPage() {
        installJapaneseTapGesture()
    }

    private func installJapaneseTapGesture() {
        removeJapaneseTapGesture()
        guard let page = visiblePage() else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleJapaneseTap(_:)))
        tap.cancelsTouchesInView = false
        page.cardView.addGestureRecognizer(tap)
        japaneseTapGesture = tap
    }

    private func removeJapaneseTapGesture() {
        if let japaneseTapGesture {
            japaneseTapGesture.view?.removeGestureRecognizer(japaneseTapGesture)
            self.japaneseTapGesture = nil
        }
    }

    @objc private func handleJapaneseTap(_ gesture: UITapGestureRecognizer) {
        guard let page = visiblePage(),
              let levelCard = page.cardView as? RegisterLadderLevelCardView
        else { return }
        let point = gesture.location(in: page.cardView)
        guard levelCard.japaneseContains(point: point, in: page.cardView) else { return }
        presentJapaneseEditor(for: levelCard.register)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func presentJapaneseEditor(for register: RegisterLadderDeck.Register) {
        let current = deck.level(for: register).japanese
        let alert = UIAlertController(
            title: "Edit \(register.title)",
            message: "Japanese shown on this slide.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = current
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard
                let self,
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            self.deck.setJapanese(text, for: register)
            if let levelCard = self.visiblePage()?.cardView as? RegisterLadderLevelCardView,
               levelCard.register == register {
                levelCard.applyJapanese(text)
            }
        })
        present(alert, animated: true)
    }
}
