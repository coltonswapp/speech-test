//
//  WordSlideshowPagerViewController.swift
//  shizen
//
//  Slideshow for a word deck: hook, then one slide per group. Swiping, export,
//  and hashtags live on ExperimentSlideshowViewController.
//

import UIKit

final class WordSlideshowPagerViewController: ExperimentSlideshowViewController {

    private let deck: WordSlideshowDeck
    private var glowPalette = WordSlideshowGlowPalette()
    private var meaningColor = ExperimentSettings.wordSlideshowMeaningColor

    override var recommendedHashtags: [String] { ExperimentHashtags.verbCombo }

    init(deck: WordSlideshowDeck) {
        self.deck = deck
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = deck.title
        super.viewDidLoad()
    }

    override func additionalExportMenuChildren() -> [UIMenuElement] {
        [
            UIAction(
                title: "Hook line",
                subtitle: deck.resolvedHookPhrase,
                image: UIImage(systemName: "text.bubble")
            ) { [weak self] _ in
                guard let self else { return }
                WordSlideshowHookPhraseEditor.present(for: self.deck, from: self) { [weak self] in
                    guard let self else { return }
                    self.replacePages(with: self.makeSlideshowPages())
                }
            },
            highlightsMenu(),
            meaningColorMenu(),
        ]
    }

    private func highlightsMenu() -> UIMenu {
        let mode = glowPalette.mode
        var shuffleItems: [UIMenuElement] = [
            UIAction(title: "Shuffled", image: UIImage(systemName: "shuffle"), state: mode == .shuffled ? .on : .off) {
                [weak self] _ in
                self?.applyGlowMode(.shuffled)
            },
        ]
        if mode == .shuffled {
            shuffleItems.append(UIAction(title: "Reshuffle", image: UIImage(systemName: "arrow.triangle.2.circlepath")) {
                [weak self] _ in
                guard let self else { return }
                self.glowPalette.reshuffle()
                self.replacePages(with: self.makeSlideshowPages())
            })
        }

        let singleColors = WordSlideshowGlowPalette.colors.map { color in
            UIAction(
                title: color.title,
                image: Self.swatch(color.uiColor),
                state: mode == .single(color) ? .on : .off
            ) { [weak self] _ in
                self?.applyGlowMode(.single(color))
            }
        }

        let subtitle: String
        switch mode {
        case .shuffled: subtitle = "Shuffled"
        case .single(let color): subtitle = color.title
        }
        return UIMenu(
            title: "Highlights",
            subtitle: subtitle,
            image: UIImage(systemName: "light.max"),
            children: [
                UIMenu(options: .displayInline, children: shuffleItems),
                UIMenu(title: "One color", options: .displayInline, children: singleColors),
            ]
        )
    }

    private func meaningColorMenu() -> UIMenu {
        let current = meaningColor
        let fixed = WordSlideshowMeaningColor.fixedOptions.map { option in
            UIAction(title: option.title, state: option == current ? .on : .off) { [weak self] _ in
                self?.applyMeaningColor(option)
            }
        }
        let hues = WordSlideshowGlowPalette.colors.map { color in
            let option = WordSlideshowMeaningColor.color(color)
            return UIAction(
                title: option.title,
                image: Self.swatch(option.textColor(glow: color)),
                state: option == current ? .on : .off
            ) { [weak self] _ in
                self?.applyMeaningColor(option)
            }
        }
        return UIMenu(
            title: "Definition color",
            subtitle: current.title,
            image: UIImage(systemName: "character.textbox"),
            children: [
                UIMenu(options: .displayInline, children: fixed),
                UIMenu(options: .displayInline, children: hues),
            ]
        )
    }

    private func applyGlowMode(_ mode: WordSlideshowGlowMode) {
        glowPalette.mode = mode
        ExperimentSettings.wordSlideshowGlowMode = mode
        replacePages(with: makeSlideshowPages())
    }

    private func applyMeaningColor(_ color: WordSlideshowMeaningColor) {
        meaningColor = color
        ExperimentSettings.wordSlideshowMeaningColor = color
        replacePages(with: makeSlideshowPages())
    }

    private static func swatch(_ color: UIColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        var pages = [
            ExperimentSlidePageViewController {
                let card = WordSlideshowHookCardView()
                card.configure(deck: self.deck)
                return card
            },
        ]
        let count = deck.groups.count
        let showsPairArrow = deck.layout == .pairs
        let meaningColor = meaningColor
        let showsExamples = deck.includesExamples
        var cardIndex = 0
        for (index, group) in deck.groups.enumerated() {
            // Captured per page so exports reuse the colors the preview shows.
            let glowColors = group.words.indices.map { glowPalette.color(forCardAt: cardIndex + $0) }
            cardIndex += group.words.count
            pages.append(
                ExperimentSlidePageViewController {
                    let card = WordSlideshowGroupCardView()
                    card.configure(
                        group: group,
                        number: index + 1,
                        count: count,
                        showsPairArrow: showsPairArrow,
                        glowColors: glowColors,
                        meaningColor: meaningColor,
                        showsExample: showsExamples
                    )
                    return card
                }
            )
            // Stacked slides have no room for examples; they get their own slide next.
            if showsExamples, group.words.count > 1, group.words.contains(where: \.hasExample) {
                pages.append(
                    ExperimentSlidePageViewController {
                        let card = WordSlideshowExamplesCardView()
                        card.configure(group: group, number: index + 1, count: count, glowColors: glowColors)
                        return card
                    }
                )
            }
        }
        return pages
    }
}

/// Alert for the hook slide's middle line, between "Do you know" and "in Japanese?".
enum WordSlideshowHookPhraseEditor {
    static func present(for deck: WordSlideshowDeck, from presenter: UIViewController, onSave: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Hook line",
            message: "\(WordSlideshowHookCardView.leadIn) … \(WordSlideshowHookCardView.closer)",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = deck.resolvedHookPhrase
            field.placeholder = "these common body parts"
            field.autocapitalizationType = .none
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Empty falls back to "these [title]".
            deck.hookPhrase = WordSlideshowDeck.cleanedHookPhrase(text)
            onSave()
        })
        presenter.present(alert, animated: true)
    }
}
