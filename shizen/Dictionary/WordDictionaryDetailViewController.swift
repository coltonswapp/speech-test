//
//  WordDictionaryDetailViewController.swift
//  shizen
//
//  Half-sheet host for WordDictionaryDetailView.
//

import InteractionKit
import UIKit

final class WordDictionaryDetailViewController: UIViewController {

    private let surface: String
    private let sentence: String?
    private let glossFraming: ContextualGlossFraming
    private let storedContext: StoredWordContext?
    private let sourceTitle: String?
    private let lineEnglish: String?
    private let allowsCommonUses: Bool
    private let keepsTappedFormAsHeadword: Bool
    private let scrollView = UIScrollView()
    private let detailView = WordDictionaryDetailView()
    private var detailTopConstraint: NSLayoutConstraint?

    /// Leading/trailing content inset, and the pre-existing top pad.
    private static let contentInset: CGFloat = 20
    /// Extra air above the ruby; matches section spacing in the detail view.
    private static let rubyClearance: CGFloat = 16

    /// Ruby paints above the headword's alignment rect into this pad, so the
    /// constant has to cover the ruby overflow plus a modest clearance at every
    /// Dynamic Type size.
    private static func headerTopPadding(for traits: UITraitCollection) -> CGFloat {
        let wordFont = UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: traits)
        let rubyOverflow = JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: wordFont)
        return max(contentInset, rubyOverflow) + rubyClearance
    }

    init(
        surface: String,
        sentence: String? = nil,
        glossFraming: ContextualGlossFraming? = nil,
        storedContext: StoredWordContext? = nil,
        sourceTitle: String? = nil,
        lineEnglish: String? = nil,
        allowsCommonUses: Bool = true,
        keepsTappedFormAsHeadword: Bool = false
    ) {
        self.surface = surface
        self.allowsCommonUses = allowsCommonUses
        self.keepsTappedFormAsHeadword = keepsTappedFormAsHeadword
        self.sentence = sentence
        self.storedContext = storedContext
        self.sourceTitle = sourceTitle
        self.lineEnglish = lineEnglish
        let trimmedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let glossFraming {
            self.glossFraming = glossFraming
        } else if !trimmedSentence.isEmpty, trimmedSentence != trimmedSurface {
            self.glossFraming = .inSentence
        } else {
            self.glossFraming = .word
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        // The sheet's top safe area changes with the detent (grabber only at
        // medium, status bar plus grabber at large). A fixed pad from the view
        // edge misses that, so pin the scroll view to the safe area directly.
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.addSubview(detailView)

        let inset = Self.contentInset
        let detailTop = detailView.topAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.topAnchor,
            constant: Self.headerTopPadding(for: traitCollection)
        )
        detailTopConstraint = detailTop
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Run to the sheet's bottom edge; the home-indicator area becomes
            // scroll inset (viewSafeAreaInsetsDidChange) instead of clipping content.
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            detailTop,
            detailView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            detailView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            detailView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            detailView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])

        detailView.onSelectCompound = { [weak self] expression in
            self?.presentCompound(expression)
        }
        detailView.onSelectKanji = { [weak self] character in
            self?.presentKanjiDetail(character)
        }
        detailView.onSelectRelatedWord = { [weak self] word in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.push(
                surface: word,
                glossFraming: .word,
                allowsCommonUses: self.allowsCommonUses,
                from: self
            )
        }
        detailView.allowsCommonUses = allowsCommonUses
        detailView.keepsTappedFormAsHeadword = keepsTappedFormAsHeadword
        if allowsCommonUses {
            detailView.onSelectCommonUsesExample = { [weak self] example in
                guard let self else { return }
                WordDictionaryDetailSheetPresenter.pushExample(example, from: self)
            }
        }
#if DEBUG
        detailView.onRequestKanjiDecomposition = { [weak self] in
            guard let self else { return }
            self.presentKanjiDecomposition(for: self.surface)
        }
#endif

        detailView.configure(
            surface: surface,
            sentence: sentence,
            glossFraming: glossFraming,
            storedContext: storedContext,
            sourceTitle: sourceTitle,
            lineEnglish: lineEnglish
        )
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let bottom = view.safeAreaInsets.bottom
        scrollView.contentInset.bottom = bottom
        scrollView.verticalScrollIndicatorInsets.bottom = bottom
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.preferredContentSizeCategory
            != previousTraitCollection?.preferredContentSizeCategory else { return }
        detailTopConstraint?.constant = Self.headerTopPadding(for: traitCollection)
    }

    private func presentCompound(_ expression: String) {
        WordDictionaryDetailSheetPresenter.push(surface: expression, from: self)
    }

    private func presentKanjiDetail(_ character: String) {
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kanjiVC = KanjiDetailViewController(character: trimmed)
        if let nav = navigationController {
            nav.pushViewController(kanjiVC, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: kanjiVC)
            kanjiVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(dismissPresentedKanji)
            )
            present(nav, animated: true)
        }
    }

    private func presentKanjiDecomposition(for surface: String) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lookup = JMDictStore.shared.lookup(forSurface: trimmed)
        let entries = lookup.entries
        let primary = entries.max { ($0.score ?? 0) < ($1.score ?? 0) } ?? entries.first

        if let primary, let word = KanjiDecompositionWord.make(from: primary) {
            presentDecompositionFormatChoice(for: word)
        } else {
            showDecomposition(KanjiDecompositionListViewController())
        }
    }

    private func presentDecompositionFormatChoice(for word: KanjiDecompositionWord) {
        let sheet = UIAlertController(
            title: word.expression,
            message: "Choose a slideshow",
            preferredStyle: .actionSheet
        )
        for format in KanjiDecompositionSlideshowFormat.allCases {
            sheet.addAction(UIAlertAction(title: format.title, style: .default) { [weak self] _ in
                ExperimentSettings.kanjiDecompositionFormat = format
                self?.showDecomposition(KanjiDecompositionPagerViewController(word: word))
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
#if DEBUG
        if let popover = sheet.popoverPresentationController {
            let anchor = detailView.kanjiDecompositionAnchorView
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
#endif
        present(sheet, animated: true)
    }

    private func showDecomposition(_ target: UIViewController) {
        if let nav = navigationController {
            nav.pushViewController(target, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: target)
            target.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(dismissPresentedKanji)
            )
            present(nav, animated: true)
        }
    }

    @objc private func dismissPresentedKanji() {
        presentedViewController?.dismiss(animated: true)
    }
}

enum WordDictionaryDetailSheetPresenter {

    static func present(
        surface: String,
        sentence: String? = nil,
        glossFraming: ContextualGlossFraming? = nil,
        storedContext: StoredWordContext? = nil,
        sourceTitle: String? = nil,
        lineEnglish: String? = nil,
        fullSheet: Bool = false,
        keepsTappedFormAsHeadword: Bool = false,
        from viewController: UIViewController,
        animated: Bool = true
    ) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Analytics.track(.wordDetailOpened, ["from_sentence": sentence != nil])

        DefinitionCalloutPresenter.shared.dismiss(animated: true)

        let sheet = WordDictionaryDetailViewController(
            surface: trimmed,
            sentence: sentence,
            glossFraming: glossFraming,
            storedContext: storedContext,
            sourceTitle: sourceTitle,
            lineEnglish: lineEnglish,
            keepsTappedFormAsHeadword: keepsTappedFormAsHeadword
        )
        configureAsSheet(sheet, fullSheet: fullSheet)
        viewController.present(sheet, animated: animated)
    }

    private static func configureAsSheet(_ sheet: UIViewController, fullSheet: Bool) {
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = fullSheet ? [.large()] : [.medium(), .large()]
            if fullSheet {
                presentation.selectedDetentIdentifier = .large
            }
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            presentation.applySolidNonLargeBackground()
        }
    }

    /// Pushes the dictionary detail onto the navigation stack instead of
    /// presenting a sheet. Falls back to a wrapped present when there is no
    /// navigation controller. Mirrors the kanji-detail push behavior.
    static func push(
        surface: String,
        sentence: String? = nil,
        glossFraming: ContextualGlossFraming? = nil,
        storedContext: StoredWordContext? = nil,
        sourceTitle: String? = nil,
        lineEnglish: String? = nil,
        allowsCommonUses: Bool = true,
        from viewController: UIViewController,
        animated: Bool = true
    ) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Analytics.track(.wordDetailOpened, ["from_sentence": sentence != nil])

        DefinitionCalloutPresenter.shared.dismiss(animated: true)

        let detail = WordDictionaryDetailViewController(
            surface: trimmed,
            sentence: sentence,
            glossFraming: glossFraming,
            storedContext: storedContext,
            sourceTitle: sourceTitle,
            lineEnglish: lineEnglish,
            allowsCommonUses: allowsCommonUses
        )
        if let nav = viewController.navigationController {
            nav.pushViewController(detail, animated: animated)
        } else {
            // No stack to push onto (e.g. a related word from a sheet): stack
            // another sheet. Wrapping it in a navigation controller left an
            // empty bar reserving space above the headword.
            configureAsSheet(detail, fullSheet: false)
            viewController.present(detail, animated: animated)
        }
    }

    /// Opens a Common Uses example in sentence scrub so each word is tappable.
    /// Missing or invalid token metadata falls through to the app tokenizer.
    /// Only one level deep: words in the example don't offer Common Uses again.
    static func pushExample(
        _ example: GeminiGrammarUsage.Example,
        from viewController: UIViewController,
        animated: Bool = true
    ) {
        let japanese = example.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !japanese.isEmpty else { return }
        DefinitionCalloutPresenter.shared.dismiss(animated: true)
        let tokens = example.scrubTokens() ?? {
            let local = JapaneseTokenizer().tokenize(japanese)
            return local.isEmpty ? nil : local
        }()
        let scrub = SentenceScrubExperimentViewController(
            sentence: japanese,
            englishTranslation: example.english,
            tokens: tokens,
            showsListenControl: true,
            allowsCommonUses: false
        )
        if let nav = viewController.navigationController {
            nav.pushViewController(scrub, animated: animated)
        } else {
            viewController.present(UINavigationController(rootViewController: scrub), animated: animated)
        }
    }
}
