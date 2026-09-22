//
//  KanjiSpotlightPagerViewController.swift
//  shizen
//
//  Slideshow for one spotlighted kanji: subject meanings first, then curated
//  compound/verb slides. Swiping, export, and hashtags live on
//  ExperimentSlideshowViewController.
//

import UIKit

final class KanjiSpotlightPagerViewController: ExperimentSlideshowViewController {

    private let deck: KanjiSpotlightDeck
    private var badgeTapGesture: UITapGestureRecognizer?
    private var introTitle = KanjiSpotlightIntroTitle.defaultTitle

    override var recommendedHashtags: [String] { ExperimentHashtags.kanji }

    init(deck: KanjiSpotlightDeck) {
        self.deck = deck
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = deck.subject.character
        super.viewDidLoad()
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        var result: [ExperimentSlidePageViewController] = [
            ExperimentSlidePageViewController {
                let cardView = KanjiSpotlightKanjiCardView()
                cardView.configure(subject: self.deck.subject, introTitle: self.introTitle)
                return cardView
            },
        ]

        let exampleCount = deck.items.count
        let spotlightCharacter = deck.subject.character
        for (index, item) in deck.items.enumerated() {
            let exampleNumber = index + 1
            result.append(
                ExperimentSlidePageViewController {
                    let cardView = KanjiSpotlightEntryCardView()
                    cardView.configure(
                        item: item,
                        exampleNumber: exampleNumber,
                        exampleCount: exampleCount,
                        spotlightCharacter: spotlightCharacter
                    )
                    return cardView
                }
            )
        }

        return result
    }

    override func additionalExportMenuChildren() -> [UIMenuElement] {
        [
            UIAction(
                title: "Slide title",
                subtitle: introTitle,
                image: UIImage(systemName: "textformat")
            ) { [weak self] _ in
                self?.presentIntroTitlePicker()
            },
            UIAction(
                title: "Highlight color",
                subtitle: ExperimentSettings.kanjiSpotlightHighlightColor.title,
                image: UIImage(systemName: "paintpalette")
            ) { [weak self] _ in
                self?.presentHighlightColors()
            },
        ]
    }

    override func slideshowDidShowPage() {
        installBadgeTapGesture()
    }

    private func installBadgeTapGesture() {
        removeBadgeTapGesture()
        guard let page = visiblePage() else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBadgeTap(_:)))
        tap.cancelsTouchesInView = false
        page.cardView.addGestureRecognizer(tap)
        badgeTapGesture = tap
    }

    private func removeBadgeTapGesture() {
        if let badgeTapGesture {
            badgeTapGesture.view?.removeGestureRecognizer(badgeTapGesture)
            self.badgeTapGesture = nil
        }
    }

    @objc private func handleBadgeTap(_ gesture: UITapGestureRecognizer) {
        guard let page = visiblePage(),
              let kanjiCard = page.cardView as? KanjiSpotlightKanjiCardView
        else { return }
        let point = gesture.location(in: page.cardView)
        if kanjiCard.titleContains(point: point, in: page.cardView) {
            presentIntroTitlePicker()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard kanjiCard.badgeContains(point: point, in: page.cardView) else { return }
        presentBadgeMeaningPicker()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func presentIntroTitlePicker() {
        let sheet = UIAlertController(
            title: "Slide title",
            message: "Shown at the top of the first slide.",
            preferredStyle: .actionSheet
        )
        for preset in KanjiSpotlightIntroTitle.presets {
            let title = preset == introTitle ? "✓ \(preset)" : preset
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.applyIntroTitle(preset)
            })
        }
        sheet.addAction(UIAlertAction(title: "Write in…", style: .default) { [weak self] _ in
            self?.presentIntroTitleWriteIn()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func presentIntroTitleWriteIn() {
        let alert = UIAlertController(
            title: "Slide title",
            message: "Write a custom title for the first slide.",
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] field in
            field.text = self?.introTitle
            field.placeholder = KanjiSpotlightIntroTitle.defaultTitle
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let typed = alert.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = typed.isEmpty ? KanjiSpotlightIntroTitle.defaultTitle : typed
            self.applyIntroTitle(title)
        })
        present(alert, animated: true)
    }

    private func applyIntroTitle(_ title: String) {
        introTitle = title
        (pages.first?.cardView as? KanjiSpotlightKanjiCardView)?.applyIntroTitle(title)
    }

    private func presentBadgeMeaningPicker() {
        let kanji = deck.subject.character
        let meanings = deck.subject.detail.meaningList
        guard !meanings.isEmpty else { return }

        let picker = KanjiDecompositionBadgeMeaningPickerViewController(
            kanji: kanji,
            meanings: meanings,
            selectedMeanings: KanjiDecompositionBadgeMeaningStore.shared.selectedMeanings(for: kanji)
        )
        picker.onSave = { [weak self] selected in
            guard let self else { return }
            KanjiDecompositionBadgeMeaningStore.shared.setSelectedMeanings(selected, for: kanji)
            let meaning = KanjidicStore.shared.detail(forKanji: kanji)?.badgeMeaning ?? ""
            for page in self.pages {
                (page.cardView as? KanjiSpotlightKanjiCardView)?.applyBadgeMeaning(meaning)
            }
        }

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func presentHighlightColors() {
        let previewExpression: String
        if currentIndex > 0, deck.items.indices.contains(currentIndex - 1) {
            previewExpression = deck.items[currentIndex - 1].expression
        } else {
            previewExpression = deck.items.first?.expression ?? deck.subject.character
        }
        let picker = KanjiSpotlightHighlightColorPickerViewController(
            previewExpression: previewExpression,
            previewHighlight: deck.subject.character
        )
        picker.onChange = { [weak self] in
            self?.refreshExampleHighlights()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func refreshExampleHighlights() {
        let color = ExperimentSettings.kanjiSpotlightHighlightColor
        for page in pages {
            (page.cardView as? KanjiSpotlightEntryCardView)?.applyHighlightColor(color)
        }
    }
}
