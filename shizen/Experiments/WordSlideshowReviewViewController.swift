//
//  WordSlideshowReviewViewController.swift
//  shizen
//
//  Checkpoint between the model and the slides: every word with its reading,
//  meaning, and dictionary warnings, one section per slide. Tap a word to fix
//  it, swipe to drop a slide, add or reorder slides from the toolbar,
//  regenerate, then make the slideshow.
//

import UIKit

final class WordSlideshowReviewViewController: UITableViewController {

    private var deck: WordSlideshowDeck
    /// The original request, when generated; nil for samples (no Regenerate).
    private let request: String?
    private var regenerateTask: Task<Void, Never>?

    private static let cellIdentifier = "WordCell"

    init(deck: WordSlideshowDeck, request: String?) {
        self.deck = deck
        self.request = request
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        regenerateTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Review"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        installBarButtons(isRegenerating: false)
        toolbarItems = [
            UIBarButtonItem(
                title: "Add slide",
                image: UIImage(systemName: "plus"),
                primaryAction: UIAction { [weak self] _ in self?.addSlide() }
            ),
            .flexibleSpace(),
            UIBarButtonItem(
                title: "Reorder",
                image: UIImage(systemName: "arrow.up.arrow.down"),
                primaryAction: UIAction { [weak self] _ in self?.reorderSlides() }
            ),
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    private func installBarButtons(isRegenerating: Bool) {
        let makeSlides = UIBarButtonItem(
            title: "Make slides",
            image: UIImage(systemName: "play.rectangle.on.rectangle"),
            primaryAction: UIAction { [weak self] _ in self?.makeSlides() }
        )
        makeSlides.isEnabled = !deck.groups.isEmpty && !isRegenerating

        var items = [makeSlides]
        if request != nil {
            if isRegenerating {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                items.append(UIBarButtonItem(customView: spinner))
            } else {
                items.append(UIBarButtonItem(
                    title: "Regenerate",
                    image: UIImage(systemName: "arrow.clockwise"),
                    primaryAction: UIAction { [weak self] _ in self?.regenerate() }
                ))
            }
        }
        navigationItem.rightBarButtonItems = items
    }

    // MARK: Actions

    private func makeSlides() {
        guard !deck.groups.isEmpty else { return }
        navigationController?.pushViewController(WordSlideshowPagerViewController(deck: deck), animated: true)
    }

    private func regenerate() {
        guard let request else { return }
        installBarButtons(isRegenerating: true)
        regenerateTask = Task { [weak self, layout = deck.layout, includeExamples = deck.includesExamples] in
            do {
                let deck = try await WordSlideshowGenerator.generate(
                    request: request,
                    layout: layout,
                    includeExamples: includeExamples
                )
                guard !Task.isCancelled, let self else { return }
                self.regenerateTask = nil
                self.deck = deck
                self.tableView.reloadData()
                self.installBarButtons(isRegenerating: false)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.regenerateTask = nil
                self.installBarButtons(isRegenerating: false)
                let alert = UIAlertController(
                    title: "Couldn't regenerate",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func editTitle() {
        let alert = UIAlertController(title: "Slideshow title", message: nil, preferredStyle: .alert)
        alert.addTextField { [deck] field in
            field.text = deck.title
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.deck.title = trimmed
            self.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        })
        present(alert, animated: true)
    }

    private func editHookPhrase() {
        WordSlideshowHookPhraseEditor.present(for: deck, from: self) { [weak self] in
            self?.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        }
    }

    private func editWord(groupIndex: Int, wordIndex: Int) {
        let word = deck.groups[groupIndex].words[wordIndex]
        let alert = UIAlertController(
            title: "Edit word",
            message: "Japanese in dictionary form, and a short English meaning.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = word.expression
            field.placeholder = "Japanese"
        }
        alert.addTextField { field in
            field.text = word.meaning
            field.placeholder = "Meaning"
            field.autocapitalizationType = .none
        }
        let editsExample = deck.includesExamples
        if editsExample {
            alert.addTextField { field in
                field.text = word.exampleJapanese
                field.placeholder = "Example (Japanese)"
            }
            alert.addTextField { field in
                field.text = word.exampleEnglish
                field.placeholder = "Example (English)"
                field.autocapitalizationType = .sentences
            }
        }
        // One-tap swaps to the dictionary's top senses (skipping the current meaning).
        let suggestions = word.dictionaryMeanings
            .filter { $0.caseInsensitiveCompare(word.meaning) != .orderedSame }
            .prefix(3)
        for suggestion in suggestions {
            alert.addAction(UIAlertAction(title: "Use “\(suggestion)”", style: .default) { [weak self] _ in
                self?.setMeaning(suggestion, groupIndex: groupIndex, wordIndex: wordIndex)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields, fields.count == (editsExample ? 4 : 2) else { return }
            let expression = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !expression.isEmpty else { return }
            self.deck.groups[groupIndex].words[wordIndex].expression = expression
            self.deck.groups[groupIndex].words[wordIndex].meaning = fields[1].text ?? ""
            if editsExample {
                self.deck.groups[groupIndex].words[wordIndex].exampleJapanese = fields[2].text ?? ""
                self.deck.groups[groupIndex].words[wordIndex].exampleEnglish = fields[3].text ?? ""
            }
            // Re-check everything: an edit can create or clear a repeat elsewhere.
            self.deck = WordSlideshowValidator.validated(self.deck)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    /// Appends a slide. Pairs and 2-per-slide take a second word (optional for
    /// 2-per-slide); a blank meaning is filled from the dictionary.
    private func addSlide() {
        let wordCount = deck.layout.wordsPerSlide
        let alert = UIAlertController(
            title: "Add slide",
            message: wordCount == 1
                ? "Japanese in dictionary form. Leave the meaning blank to use the dictionary's."
                : "Two words, top then bottom. Leave a meaning blank to use the dictionary's.",
            preferredStyle: .alert
        )
        for index in 0..<wordCount {
            let suffix = wordCount == 1 ? "" : " \(index + 1)"
            alert.addTextField { field in
                field.placeholder = "Japanese\(suffix)"
            }
            alert.addTextField { field in
                field.placeholder = "Meaning\(suffix) (optional)"
                field.autocapitalizationType = .none
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            let words = stride(from: 0, to: fields.count - 1, by: 2).compactMap { index -> WordSlideshowWord? in
                let expression = fields[index].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !expression.isEmpty else { return nil }
                return WordSlideshowWord(expression: expression, meaning: fields[index + 1].text ?? "")
            }
            guard !words.isEmpty else { return }
            self.deck.groups.append(WordSlideshowGroup(words: words))
            self.deck = WordSlideshowValidator.validated(self.deck)
            self.tableView.reloadData()
            self.installBarButtons(isRegenerating: self.regenerateTask != nil)
            let lastSection = self.tableView.numberOfSections - 1
            self.tableView.scrollToRow(at: IndexPath(row: 0, section: lastSection), at: .middle, animated: true)
            if self.deck.includesExamples {
                self.fillMissingExamples()
            }
        })
        present(alert, animated: true)
    }

    /// Writes examples for words that have none (added slides, failed calls).
    private func fillMissingExamples() {
        guard WordSlideshowGenerator.isAvailable else { return }
        let deck = deck
        Task { [weak self] in
            await WordSlideshowGenerator.fillExamples(in: deck)
            guard let self, self.deck === deck else { return }
            self.tableView.reloadData()
        }
    }

    private func regenerateExample(groupIndex: Int, wordIndex: Int) {
        let deck = deck
        let word = deck.groups[groupIndex].words[wordIndex]
        Task { [weak self] in
            do {
                let example = try await WordSlideshowGenerator.example(for: word)
                guard let self, self.deck === deck,
                      deck.groups.indices.contains(groupIndex),
                      deck.groups[groupIndex].words.indices.contains(wordIndex),
                      deck.groups[groupIndex].words[wordIndex].expression == word.expression
                else { return }
                deck.groups[groupIndex].words[wordIndex].exampleJapanese = example.japanese
                deck.groups[groupIndex].words[wordIndex].exampleEnglish = example.english
                self.deck = WordSlideshowValidator.validated(deck)
                self.tableView.reloadData()
            } catch {
                guard let self else { return }
                let alert = UIAlertController(
                    title: "Couldn't write an example",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func reorderSlides() {
        guard deck.groups.count > 1 else { return }
        let reorder = WordSlideshowReorderViewController(groups: deck.groups) { [weak self] groups in
            guard let self else { return }
            self.deck.groups = groups
            self.tableView.reloadData()
        }
        present(UINavigationController(rootViewController: reorder), animated: true)
    }

    private func setMeaning(_ meaning: String, groupIndex: Int, wordIndex: Int) {
        deck.groups[groupIndex].words[wordIndex].meaning = meaning
        deck = WordSlideshowValidator.validated(deck)
        tableView.reloadData()
    }

    private func deleteSlide(groupIndex: Int) {
        deck.groups.remove(at: groupIndex)
        deck = WordSlideshowValidator.validated(deck)
        tableView.reloadData()
        installBarButtons(isRegenerating: regenerateTask != nil)
    }

    // MARK: Table

    /// Section 0 is the title and hook line; each later section is one word slide.
    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + deck.groups.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : deck.groups[section - 1].words.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // The hook is slide 1, so word slides start at 2.
        section == 0 ? "Title · \(deck.layout.title)" : "Slide \(section + 1)"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let words = deck.allWords
            let verified = words.filter(\.isVerified).count
            return "\(verified) of \(words.count) words match the dictionary. Tap a word to edit it. Swipe left to use the dictionary's meaning or remove a slide."
        }
        let warnings = deck.groups[section - 1].warnings
        return warnings.isEmpty ? nil : "⚠︎ " + warnings.joined(separator: " · ")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        if indexPath.section == 0, indexPath.row == 0 {
            content.text = deck.title
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.image = UIImage(systemName: "textformat")
            content.imageProperties.tintColor = .secondaryLabel
        } else if indexPath.section == 0 {
            content.text = deck.resolvedHookPhrase
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = "\(WordSlideshowHookCardView.leadIn) … \(WordSlideshowHookCardView.closer) · first slide"
            content.image = UIImage(systemName: "text.bubble")
            content.imageProperties.tintColor = .secondaryLabel
        } else {
            let word = deck.groups[indexPath.section - 1].words[indexPath.row]
            content.text = word.reading.isEmpty || word.reading == word.expression
                ? word.expression
                : "\(word.expression)  \(word.reading)"
            content.textProperties.font = .systemFont(ofSize: 20, weight: .semibold)

            var lines = [word.meaning.isEmpty ? "No meaning" : word.meaning]
            if word.hasExample {
                lines.append("例 \(word.exampleJapanese)")
                if !word.exampleEnglish.isEmpty { lines.append(word.exampleEnglish) }
            }
            if !word.isVerified {
                lines.append("⚠︎ " + word.warnings.joined(separator: " · "))
            }
            content.secondaryText = lines.joined(separator: "\n")
            content.image = UIImage(systemName: word.isVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            content.imageProperties.tintColor = word.isVerified ? .systemGreen : .systemOrange
        }

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            indexPath.row == 0 ? editTitle() : editHookPhrase()
        } else {
            editWord(groupIndex: indexPath.section - 1, wordIndex: indexPath.row)
        }
    }

    /// Swipe left: remove the slide, and for a word whose meaning the dictionary
    /// doesn't list, take the dictionary's main sense instead.
    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section > 0 else { return nil }
        let groupIndex = indexPath.section - 1
        let wordIndex = indexPath.row

        // First action sits outermost and is the full-swipe action, as before.
        var actions = [
            UIContextualAction(style: .destructive, title: "Remove slide") { [weak self] _, _, completion in
                self?.deleteSlide(groupIndex: groupIndex)
                completion(true)
            },
        ]

        let word = deck.groups[groupIndex].words[wordIndex]
        if !word.meaningMatchesDictionary, let dictionaryMeaning = word.dictionaryMeanings.first {
            let swap = UIContextualAction(style: .normal, title: "Use “\(dictionaryMeaning)”") { [weak self] _, _, completion in
                self?.setMeaning(dictionaryMeaning, groupIndex: groupIndex, wordIndex: wordIndex)
                completion(true)
            }
            swap.image = UIImage(systemName: "book.closed")
            swap.backgroundColor = .systemBlue
            actions.append(swap)
        }
        if deck.includesExamples, WordSlideshowGenerator.isAvailable {
            let newExample = UIContextualAction(style: .normal, title: "New example") { [weak self] _, _, completion in
                self?.regenerateExample(groupIndex: groupIndex, wordIndex: wordIndex)
                completion(true)
            }
            newExample.image = UIImage(systemName: "text.quote")
            newExample.backgroundColor = .systemIndigo
            actions.append(newExample)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }
}

// MARK: - Reorder

/// One row per slide with drag handles. Done hands back the new order.
private final class WordSlideshowReorderViewController: UITableViewController {
    private var groups: [WordSlideshowGroup]
    private let onDone: ([WordSlideshowGroup]) -> Void

    init(groups: [WordSlideshowGroup], onDone: @escaping ([WordSlideshowGroup]) -> Void) {
        self.groups = groups
        self.onDone = onDone
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reorder slides"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Slide")
        tableView.isEditing = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.onDone(self.groups)
            self.dismiss(animated: true)
        })
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "The hook stays first. Drag to change the order of the word slides."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Slide", for: indexPath)
        let words = groups[indexPath.row].words
        var content = UIListContentConfiguration.subtitleCell()
        content.text = words.map(\.expression).joined(separator: " · ")
        content.textProperties.font = .systemFont(ofSize: 18, weight: .semibold)
        content.secondaryText = words.map(\.meaning).joined(separator: " · ")
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let moved = groups.remove(at: sourceIndexPath.row)
        groups.insert(moved, at: destinationIndexPath.row)
    }
}
