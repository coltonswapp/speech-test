//
//  SavedVocabularyListViewController.swift
//  shizen
//
//  Words in a saved-vocabulary folder. Flashcards are a top-right option.
//

import UIKit

final class SavedVocabularyListViewController: UIViewController {

    private let folderID: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items: [SavedVocabularyItem] = []

    private let emptyView = UIView()
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No saved words yet.\nSave a word from the dictionary to see it here."
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var flashcardsButton = UIBarButtonItem(
        image: UIImage(systemName: "rectangle.stack"),
        style: .plain,
        target: self,
        action: #selector(openFlashcards)
    )

    init(folderID: String = SavedVocabularyStore.inboxID) {
        self.folderID = folderID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = SavedVocabularyStore.shared.folder(id: folderID)?.name ?? "Saved vocabulary"
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never
        flashcardsButton.accessibilityLabel = "Flashcards"
        navigationItem.rightBarButtonItem = flashcardsButton

        setupTableView()
        observeStore()
        reloadItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadItems()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = ExperimentPalette.pageBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WordCell")
        emptyView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: emptyView.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: emptyView.trailingAnchor, constant: -32),
        ])
        tableView.backgroundView = emptyView
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeStore() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreDidChange),
            name: SavedVocabularyStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleStoreDidChange() {
        reloadItems()
    }

    private func reloadItems() {
        title = SavedVocabularyStore.shared.folder(id: folderID)?.name ?? "Saved vocabulary"
        items = SavedVocabularyStore.shared.items(inFolderID: folderID)
        emptyView.isHidden = !items.isEmpty
        flashcardsButton.isEnabled = !items.isEmpty
        tableView.reloadData()
    }

    @objc private func openFlashcards() {
        let cards = items.map(\.flashcard)
        guard !cards.isEmpty else { return }
        let flashcards = FlashcardExperimentViewController(
            title: title ?? "Flashcards",
            cards: cards
        )
        navigationController?.pushViewController(flashcards, animated: true)
    }

    private static func subtitle(for item: SavedVocabularyItem) -> String {
        var parts: [String] = []
        if let reading = item.reading, reading != item.surface {
            parts.append(reading)
        }
        if let gloss = item.gloss, !gloss.isEmpty {
            parts.append(gloss)
        } else if let sentence = item.sentence, !sentence.isEmpty {
            parts.append(sentence)
        }
        return parts.joined(separator: " · ")
    }
}

extension SavedVocabularyListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WordCell", for: indexPath)
        let item = items[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = item.surface
        configuration.textProperties.font = .preferredFont(forTextStyle: .title3)
        configuration.secondaryText = Self.subtitle(for: item)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = ExperimentPalette.cardSurface
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else { return }
        let item = items[indexPath.row]
        WordDictionaryDetailSheetPresenter.push(
            surface: item.surface,
            sentence: item.sentence,
            from: self
        )
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self, self.items.indices.contains(indexPath.row) else {
                completion(false)
                return
            }
            SavedVocabularyStore.shared.remove(id: self.items[indexPath.row].id, fromFolderID: self.folderID)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
