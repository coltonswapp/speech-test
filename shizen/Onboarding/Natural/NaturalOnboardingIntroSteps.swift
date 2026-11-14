//
//  NaturalOnboardingIntroSteps.swift
//  shizen
//
//  Hana says hello, gets a name and a level, then sets up the gap between
//  textbook and spoken Japanese.
//
//  Type rule: chat bubbles carry English only (the hello). Japanese always
//  appears the Dialogue way: a glass bubble or display line, English under it.
//

import NNKit
import UIKit

// MARK: - Hello

final class NaturalIntroStepViewController: NaturalStepViewController {

    override var progressBeatCount: Int { 4 }

    private var chat: TutorChatView?
    private let composer = TutorNameComposer()
    /// Where the floating Hana (listen-first v2) peeks up from: sitting on the screen's bottom edge.
    private let hanaSpot = UIView()
    private var hasPickedLevel = false

    override func buildStage() {
        setupOnboarding(title: "Welcome to Shizen", subtitle: "Natural Japanese, one conversation at a time.")
        hasPickedLevel = false

        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        self.chat = chat
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)

        composer.install(in: view, above: stage)
        composer.onSubmit = { [weak self] name in self?.submitName(name) }
        composer.reset()

        if hanaStage != nil {
            // On `view` so it can reach the very bottom edge. Re-added each build so constraints don't pile up.
            hanaSpot.removeFromSuperview()
            hanaSpot.translatesAutoresizingMaskIntoConstraints = false
            hanaSpot.isUserInteractionEnabled = false
            view.addSubview(hanaSpot)
            NSLayoutConstraint.activate([
                hanaSpot.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hanaSpot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hanaSpot.widthAnchor.constraint(equalToConstant: 150),
                hanaSpot.heightAnchor.constraint(equalToConstant: 150),
            ])
        }
    }

    /// The peek runs from `play`; coming back to this screen, Hana is in the chat.
    override func hanaStageDidAppear(firstTime: Bool) {
        if !firstTime {
            hanaStage?.hide()
        }
    }

    override func play() {
        let chatDelay = playHanaPeek()
        timeline.after(chatDelay) { [weak self] in
            self?.chat?.play([.tutorText("Hi, I'm Hana.")]) { [weak self] in
                self?.showSkipHintIfFirstRun()
                self?.chat?.play([
                    .tutorText("I'll help you understand Japanese the way people actually speak it."),
                    .tutorText("What should I call you?"),
                ]) { [weak self] in
                    self?.composer.open()
                }
            }
        }
    }

    override func resetStage() {
        composer.dismissKeyboard()
        super.resetStage()
    }

    /// Hana rises from below the bottom edge until just her eyes show, glances around,
    /// then hops up. Her first line starts typing right after, and she flies up into it.
    /// Returns when the chat should start.
    private func playHanaPeek() -> TimeInterval {
        guard let hanaStage else { return 0.35 }
        view.layoutIfNeeded()
        // Past full peek, so she starts completely out of sight below the edge.
        hanaStage.mascot.set(MascotExpression([.peek: 1.8, .lookY: -0.2]), animated: false)
        hanaStage.appear(at: hanaSpot.convert(hanaSpot.bounds, to: nil))

        // A touch short of full peek so both eyes clear the edge.
        var peeking = MascotPreset.peek.expression
        peeking[.peek] = 0.85
        var lookingLeft = peeking
        lookingLeft[.lookX] = -0.9
        var lookingRight = peeking
        lookingRight[.lookX] = 0.9
        let mascot = hanaStage.mascot
        timeline.after(0.5) { mascot.set(peeking) }
        timeline.after(1.3) { mascot.set(lookingLeft) }
        timeline.after(1.9) { mascot.set(lookingRight) }
        timeline.after(2.5) { mascot.set(MascotPreset.happy.expression) }
        return 3.1
    }

    private func submitName(_ submitted: String) {
        natural.name = submitted
        composer.close(in: view)

        let name = natural.displayName
        advanceProgressBeat(to: 1)
        chat?.play([
            .userText(name),
            .tutorText("Nice to meet you, \(name)."),
            .tutorText("How much Japanese do you know so far?"),
        ]) { [weak self] in
            self?.showLevelCards()
        }
    }

    private func showLevelCards() {
        let cards = TutorLevel.allCases.map { level in
            let card = OnboardingSummaryCard()
            card.text = level.title
            card.tag = level.rawValue
            card.addTarget(self, action: #selector(levelCardTapped(_:)), for: .touchUpInside)
            return card
        }
        chat?.appendCustom(cards, stagger: 0.07, scrollDuration: 0.4)
    }

    @objc private func levelCardTapped(_ card: OnboardingSummaryCard) {
        guard !hasPickedLevel else { return }
        hasPickedLevel = true
        card.isChosen = true
        natural.level = TutorLevel(rawValue: card.tag) ?? .brandNew
        playSelectionHaptic()
        explodeEmoji(from: card, preset: .tiny)
        advanceProgressBeat(to: 2)
        timeline.after(0.6) { [weak self] in
            self?.chat?.clear { [weak self] in
                self?.playIdea()
            }
        }
    }

    /// Second set, from a clean slate: the setup for Textbooks vs. real life.
    private func playIdea() {
        guard let chat else { return }
        advanceProgressBeat(to: 3)
        timeline.after(0.2) { [weak self] in
            chat.play([
                .tutorText("Here's something most apps won't tell you."),
                .tutorText("The Japanese in textbooks isn't the Japanese people speak. Real speech is squashed, shortened, and fast."),
                .tutorText("That's why real conversations sound like noise at first. Let me show you."),
            ]) { [weak self] in
                self?.revealCTA("Show me")
            }
        }
    }
}



