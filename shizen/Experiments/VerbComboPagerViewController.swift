//
//  VerbComboPagerViewController.swift
//  shizen
//
//  Five exportable stills: hook verb, rule, then three examples.
//

import UIKit

final class VerbComboPagerViewController: ExperimentSlideshowViewController {

    private let deck: VerbComboDeck

    override var recommendedHashtags: [String] { ExperimentHashtags.verbCombo }

    init(deck: VerbComboDeck) {
        self.deck = deck
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = deck.hookVerb
        super.viewDidLoad()
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        var pages = [
            ExperimentSlidePageViewController {
                let card = VerbComboHookCardView()
                card.configure(hookVerb: self.deck.hookVerb)
                return card
            },
            ExperimentSlidePageViewController {
                let card = VerbComboRuleCardView()
                card.configure(rule: self.deck.rule)
                return card
            },
        ]
        for example in deck.examples {
            pages.append(
                ExperimentSlidePageViewController {
                    let card = VerbComboExampleCardView()
                    card.configure(example: example)
                    return card
                }
            )
        }
        return pages
    }
}
