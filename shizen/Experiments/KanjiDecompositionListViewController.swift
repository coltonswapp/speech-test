//
//  KanjiDecompositionListViewController.swift
//  shizen
//
//  Word picker for the kanji decomposition card experiment: a UICollectionView list,
//  seeded from JMDict 2- and 3-kanji compounds, refined by search. Tapping a row
//  pushes the slideshow pager for that word.
//

import UIKit

final class KanjiDecompositionListViewController: UIViewController {

    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, KanjiDecompositionWord>!

    private var words: [KanjiDecompositionWord] = []
    private var isLoadingSeed = false
    private var searchTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kanji Decomposition"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never

        setupSearchController()
        setupCollectionView()
        loadSeedWords()
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search kanji compounds…"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupCollectionView() {
        cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, KanjiDecompositionWord> { cell, _, word in
            var configuration = cell.defaultContentConfiguration()
            configuration.text = word.expression
            configuration.textProperties.font = .preferredFont(forTextStyle: .title3)
            let countLabel = word.characters.count == 3 ? "3-kanji · " : "2-kanji · "
            configuration.secondaryText = "\(countLabel)\(word.entry.displayReading) · \(word.entry.firstGloss)"
            configuration.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = configuration
            cell.accessories = [.disclosureIndicator()]
        }

        var layoutConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
        layoutConfiguration.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: layoutConfiguration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadSeedWords() {
        isLoadingSeed = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let entries = JMDictStore.shared.kanjiCompounds(characterCounts: [2, 3], limit: 300)
            var seen = Set<String>()
            var seeded: [KanjiDecompositionWord] = []
            for entry in entries {
                guard let word = KanjiDecompositionWord.make(from: entry), seen.insert(word.expression).inserted else { continue }
                seeded.append(word)
                if seeded.count >= 60 { break }
            }
            await MainActor.run {
                guard let self else { return }
                self.isLoadingSeed = false
                self.words = seeded
                self.collectionView.reloadData()
            }
        }
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadSeedWords()
            return
        }
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let found = JMDictStore.shared.search(query: trimmed)
            var seen = Set<String>()
            var filtered: [KanjiDecompositionWord] = []
            for entry in found {
                guard let word = KanjiDecompositionWord.make(from: entry), seen.insert(word.expression).inserted else { continue }
                filtered.append(word)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.words = filtered
                self.collectionView.reloadData()
            }
        }
    }
}

// MARK: - UISearchResultsUpdating

extension KanjiDecompositionListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        runSearch(searchController.searchBar.text ?? "")
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension KanjiDecompositionListViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        words.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: words[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let word = words[indexPath.item]
        navigationController?.pushViewController(KanjiDecompositionPagerViewController(word: word), animated: true)
    }
}
