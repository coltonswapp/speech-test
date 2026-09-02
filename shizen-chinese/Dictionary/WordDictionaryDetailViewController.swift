//
//  WordDictionaryDetailViewController.swift
//  shizen-chinese
//
//  Host for WordDictionaryDetailView, with save-to-deck.
//

import UIKit

final class WordDictionaryDetailViewController: UIViewController {

    private let surface: String
    private let sentence: String?
    private let scrollView = UIScrollView()
    private let detailView = WordDictionaryDetailView()

    init(surface: String, sentence: String? = nil) {
        self.surface = surface
        self.sentence = sentence
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(entry: CedictEntry) {
        self.init(surface: entry.simplified)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = surface
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(detailView)

        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            detailView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: inset),
            detailView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            detailView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            detailView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            detailView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])

        detailView.onSelectCompound = { [weak self] expression in
            self?.pushDetail(surface: expression)
        }
        detailView.onSelectCharacter = { [weak self] character in
            self?.pushDetail(surface: character)
        }
        detailView.configure(surface: surface, sentence: sentence)
    }

    private func pushDetail(surface: String) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        navigationController?.pushViewController(
            WordDictionaryDetailViewController(surface: trimmed),
            animated: true
        )
    }

    @objc private func saveTapped() {
        guard let entry = detailView.primaryEntry else {
            let alert = UIAlertController(
                title: "Can't save",
                message: "No dictionary entry to add to a deck.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(title: "Save to deck", message: entry.simplified, preferredStyle: .actionSheet)
        for deck in DeckStore.shared.decks {
            sheet.addAction(UIAlertAction(title: deck.name, style: .default) { [weak self] _ in
                self?.save(entry: entry, toDeckID: deck.id, deckName: deck.name)
            })
        }
        sheet.addAction(UIAlertAction(title: "New deck…", style: .default) { [weak self] _ in
            self?.promptNewDeck(entry: entry)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func promptNewDeck(entry: CedictEntry) {
        let alert = UIAlertController(title: "New deck", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Deck name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text ?? ""
            let deck = DeckStore.shared.createDeck(name: name)
            self.save(entry: entry, toDeckID: deck.id, deckName: deck.name)
        })
        present(alert, animated: true)
    }

    private func save(entry: CedictEntry, toDeckID deckID: String, deckName: String) {
        let added = DeckStore.shared.add(entry: entry, toDeckID: deckID)
        let message = added
            ? "Saved to \(deckName)."
            : "Already in \(deckName)."
        let confirm = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "OK", style: .default))
        present(confirm, animated: true)
    }
}
