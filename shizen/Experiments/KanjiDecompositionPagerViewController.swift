//
//  KanjiDecompositionPagerViewController.swift
//  shizen
//
//  Slideshow for a decomposed word. Full format: intro, one slide per component,
//  a teaser, then the combined reveal. Short format: the kanji, the parts stacked,
//  then the word and its meaning. Swiping, export, and hashtags live on
//  ExperimentSlideshowViewController.
//

import UIKit

final class KanjiDecompositionPagerViewController: ExperimentSlideshowViewController {

    private let word: KanjiDecompositionWord
    private let badgeLayoutStore = KanjiDecompositionBadgeLayoutStore()
    private let formatControl = UISegmentedControl(
        items: KanjiDecompositionSlideshowFormat.allCases.map(\.shortTitle)
    )
    private var format = ExperimentSettings.kanjiDecompositionFormat
    private var isPositioningBadges = false
    private var selectedBadgeIdentifier: KanjiDecompositionBadgeIdentifier?
    private var badgePanStartOffset: CGPoint = .zero
    private var badgeTapGesture: UITapGestureRecognizer?
    private var badgeLongPressGesture: UILongPressGestureRecognizer?
    private var badgePanGesture: UIPanGestureRecognizer?
    private var introPartLabel = KanjiDecompositionPartLabelStore.nextPartLabel()
    /// Session-only override for the final gloss on the last slide.
    private var definitionOverride: String?

    override var recommendedHashtags: [String] { ExperimentHashtags.kanji }

    init(word: KanjiDecompositionWord) {
        self.word = word
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = word.expression
        formatControl.selectedSegmentIndex = KanjiDecompositionSlideshowFormat.allCases.firstIndex(of: format) ?? 0
        formatControl.accessibilityLabel = "Slideshow format"
        formatControl.addAction(UIAction { [weak self] _ in
            self?.formatControlChanged()
        }, for: .valueChanged)
        super.viewDidLoad()
    }

    override func supplementaryPreviewControl() -> UIView? {
        formatControl
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        switch format {
        case .full: return makeFullPages()
        case .short: return makeShortPages()
        }
    }

    override func slideshowDidShowPage() {
        installBadgeLayoutGestures()
        installFinalDefinitionEditGesture()
    }

    override func slideshowDidFinishPageTransition() {
        if isPositioningBadges {
            selectedBadgeIdentifier = nil
            setBadgeEditingSelection(nil)
        }
        super.slideshowDidFinishPageTransition()
    }

    override func slideshowDidSaveAllPhotos() {
        KanjiDecompositionPartLabelStore.recordExport(from: introPartLabel)
    }

    private func formatControlChanged() {
        let index = formatControl.selectedSegmentIndex
        guard KanjiDecompositionSlideshowFormat.allCases.indices.contains(index) else { return }
        applyFormat(KanjiDecompositionSlideshowFormat.allCases[index])
    }

    private func applyFormat(_ format: KanjiDecompositionSlideshowFormat) {
        guard format != self.format else { return }
        if isPositioningBadges {
            endBadgePositioning()
        }
        self.format = format
        ExperimentSettings.kanjiDecompositionFormat = format
        formatControl.selectedSegmentIndex = KanjiDecompositionSlideshowFormat.allCases.firstIndex(of: format) ?? 0
        replacePages(with: makeSlideshowPages())
    }

    private func makePage(_ makeCardView: @escaping () -> UIView) -> ExperimentSlidePageViewController {
        ExperimentSlidePageViewController(makeCardView: makeCardView) { [badgeLayoutStore] card in
            badgeLayoutStore.apply(to: card)
        }
    }

    private func makeShortPages() -> [ExperimentSlidePageViewController] {
        [
            makePage {
                let cardView = KanjiDecompositionIntroCardView()
                cardView.configure(word: self.word, partLabel: self.introPartLabel)
                return cardView
            },
            makePage {
                let cardView = KanjiDecompositionStackedPartsCardView()
                cardView.configure(word: self.word)
                return cardView
            },
            makePage {
                let cardView = KanjiDecompositionCombinedCardView()
                cardView.configure(
                    word: self.word,
                    meaningOverride: self.definitionOverride,
                    showsParts: false
                )
                return cardView
            },
        ]
    }

    private func makeFullPages() -> [ExperimentSlidePageViewController] {
        var result: [ExperimentSlidePageViewController] = [
            makePage {
                let cardView = KanjiDecompositionIntroCardView()
                cardView.configure(word: self.word, partLabel: self.introPartLabel)
                return cardView
            },
        ]

        for (index, character) in word.characters.enumerated() {
            result.append(
                makePage {
                    let cardView = KanjiDecompositionCharacterCardView(
                        badgeIdentifier: .character(index: index)
                    )
                    cardView.configure(character: character, excludingExpression: self.word.expression)
                    return cardView
                }
            )
        }

        result.append(
            makePage {
                let cardView = KanjiDecompositionTeaserCardView()
                cardView.configure(word: self.word)
                return cardView
            }
        )

        result.append(
            makePage {
                let cardView = KanjiDecompositionCombinedCardView()
                cardView.configure(word: self.word, meaningOverride: self.definitionOverride)
                return cardView
            }
        )

        return result
    }

    private func installFinalDefinitionEditGesture() {
        for page in pages {
            (page.cardView as? KanjiDecompositionCombinedCardView)?
                .installMeaningTapGesture(target: self, action: #selector(handleFinalDefinitionTap(_:)))
        }
    }

    private var effectiveFinalDefinitionText: String {
        definitionOverride ?? word.entry.firstGloss
    }

    private func applyFinalDefinitionOverrideToCards() {
        let text = effectiveFinalDefinitionText
        for page in pages {
            (page.cardView as? KanjiDecompositionCombinedCardView)?.applyMeaningText(text)
        }
    }

    @objc private func handleFinalDefinitionTap(_ gesture: UITapGestureRecognizer) {
        guard !isPositioningBadges else { return }

        let picker = KanjiDecompositionFinalDefinitionPickerViewController(
            definitions: word.allDefinitionOptions,
            selectedDefinition: effectiveFinalDefinitionText
        )
        picker.onSave = { [weak self] chosen in
            guard let self else { return }
            if let chosen {
                self.definitionOverride = (chosen == self.word.entry.firstGloss) ? nil : chosen
            } else {
                self.definitionOverride = nil
            }
            self.applyFinalDefinitionOverrideToCards()
        }

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func beginBadgePositioning(selecting identifier: KanjiDecompositionBadgeIdentifier? = nil) {
        isPositioningBadges = true
        selectedBadgeIdentifier = identifier
        setPageScrollingEnabled(false)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(endBadgePositioning)
        )
        hideExportButton()
        setPageControlEnabled(false)
        setBadgeEditingSelection(identifier)
    }

    @objc private func endBadgePositioning() {
        isPositioningBadges = false
        selectedBadgeIdentifier = nil
        setPageScrollingEnabled(true)
        navigationItem.leftBarButtonItem = nil
        restoreExportButton()
        setPageControlEnabled(true)
        setBadgeEditingSelection(nil)
    }

    private func setBadgeEditingSelection(_ identifier: KanjiDecompositionBadgeIdentifier?) {
        (visiblePage()?.cardView as? KanjiDecompositionBadgeLayoutHost)?
            .setBadgeEditingSelection(identifier)
    }

    private func presentPartLabelEditor() {
        let alert = UIAlertController(
            title: "Part label",
            message: "Shown above the question on slide 1.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = self.introPartLabel
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard
                let self,
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            self.introPartLabel = text
            (self.pages.first?.cardView as? KanjiDecompositionIntroCardView)?.applyPartLabel(text)
        })
        present(alert, animated: true)
    }

    private func installBadgeLayoutGestures() {
        removeBadgeLayoutGestures()
        guard let page = visiblePage() else { return }

        let target = page.cardView
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBadgeLayoutTap(_:)))
        tap.cancelsTouchesInView = false
        target.addGestureRecognizer(tap)
        badgeTapGesture = tap

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleBadgeLayoutLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = true
        target.addGestureRecognizer(longPress)
        badgeLongPressGesture = longPress

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBadgeLayoutPan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        target.addGestureRecognizer(pan)
        badgePanGesture = pan
    }

    private func removeBadgeLayoutGestures() {
        if let badgeTapGesture {
            badgeTapGesture.view?.removeGestureRecognizer(badgeTapGesture)
            self.badgeTapGesture = nil
        }
        if let badgeLongPressGesture {
            badgeLongPressGesture.view?.removeGestureRecognizer(badgeLongPressGesture)
            self.badgeLongPressGesture = nil
        }
        if let badgePanGesture {
            badgePanGesture.view?.removeGestureRecognizer(badgePanGesture)
            self.badgePanGesture = nil
        }
    }

    @objc private func handleBadgeLayoutTap(_ gesture: UITapGestureRecognizer) {
        guard let page = visiblePage() else { return }
        let point = gesture.location(in: page.cardView)

        if let intro = page.cardView as? KanjiDecompositionIntroCardView,
           intro.eyebrowContains(point: point, in: page.cardView) {
            presentPartLabelEditor()
            return
        }

        guard let host = page.cardView as? KanjiDecompositionBadgeLayoutHost else { return }
        for hero in host.characterHeroViews() where hero.badgeContains(point: point, in: page.cardView) {
            if isPositioningBadges {
                selectedBadgeIdentifier = hero.layoutIdentifier
                setBadgeEditingSelection(selectedBadgeIdentifier)
            } else {
                presentBadgeMeaningPicker(for: hero.layoutIdentifier)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard isPositioningBadges else { return }
        selectedBadgeIdentifier = nil
        setBadgeEditingSelection(nil)
    }

    @objc private func handleBadgeLayoutLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isPositioningBadges, let page = visiblePage() else { return }
        let point = gesture.location(in: page.cardView)
        guard let host = page.cardView as? KanjiDecompositionBadgeLayoutHost else { return }
        for hero in host.characterHeroViews() where hero.badgeContains(point: point, in: page.cardView) {
            beginBadgePositioning(selecting: hero.layoutIdentifier)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
    }

    private func presentBadgeMeaningPicker(for identifier: KanjiDecompositionBadgeIdentifier) {
        guard let character = character(for: identifier) else { return }
        let kanji = String(character)
        let meanings = KanjidicStore.shared.detail(forKanji: kanji)?.meaningList ?? []
        guard !meanings.isEmpty else { return }

        let picker = KanjiDecompositionBadgeMeaningPickerViewController(
            kanji: kanji,
            meanings: meanings,
            selectedMeanings: KanjiDecompositionBadgeMeaningStore.shared.selectedMeanings(for: kanji)
        )
        picker.onSave = { [weak self] selected in
            guard let self else { return }
            KanjiDecompositionBadgeMeaningStore.shared.setSelectedMeanings(selected, for: kanji)
            self.applyBadgeMeaning(for: character)
        }

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func character(for identifier: KanjiDecompositionBadgeIdentifier) -> Character? {
        let index: Int
        switch identifier {
        case .character(let i), .combinedPreview(let i), .stacked(let i):
            index = i
        }
        guard word.characters.indices.contains(index) else { return nil }
        return word.characters[index]
    }

    private func applyBadgeMeaning(for character: Character) {
        let kanji = String(character)
        let meaning = KanjidicStore.shared.detail(forKanji: kanji)?.badgeMeaning ?? ""
        for page in pages {
            guard let host = page.cardView as? KanjiDecompositionBadgeLayoutHost else { continue }
            for hero in host.characterHeroViews() {
                guard self.character(for: hero.layoutIdentifier) == character else { continue }
                hero.applyMeaning(meaning)
            }
        }
    }

    @objc private func handleBadgeLayoutPan(_ gesture: UIPanGestureRecognizer) {
        guard
            isPositioningBadges,
            let identifier = selectedBadgeIdentifier,
            let page = visiblePage(),
            let host = page.cardView as? KanjiDecompositionBadgeLayoutHost,
            let hero = host.characterHeroViews().first(where: { $0.layoutIdentifier == identifier })
        else { return }

        switch gesture.state {
        case .began:
            badgePanStartOffset = badgeLayoutStore.offset(for: identifier)
        case .changed:
            let translation = gesture.translation(in: page.cardView)
            let offset = CGPoint(
                x: badgePanStartOffset.x + translation.x,
                y: badgePanStartOffset.y + translation.y
            )
            badgeLayoutStore.setOffset(offset, for: identifier)
            hero.applyUserOffset(offset)
        default:
            break
        }
    }
}

extension KanjiDecompositionPagerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === badgePanGesture {
            return isPositioningBadges && selectedBadgeIdentifier != nil
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
