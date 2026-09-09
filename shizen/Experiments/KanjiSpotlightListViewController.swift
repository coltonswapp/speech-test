//
//  KanjiSpotlightListViewController.swift
//  shizen
//
//  Kanji picker for the Kanji Spotlight slideshow: seeded from high-frequency
//  kanjidic entries, refined by search. Tapping a row opens the curator.
//

import UIKit

final class KanjiSpotlightListViewController: UIViewController {

    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, KanjiSpotlightSubject>!

    private var subjects: [KanjiSpotlightSubject] = []
    private var isLoadingSeed = false
    private var searchTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kanji Spotlight"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never

        setupSearchController()
        setupCollectionView()
        loadSeedKanji()
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search kanji, meaning, reading…"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupCollectionView() {
        cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, KanjiSpotlightSubject> {
            cell, _, subject in
            var configuration = cell.defaultContentConfiguration()
            configuration.text = subject.character
            configuration.textProperties.font = .preferredFont(forTextStyle: .title2)

            let readings = subject.detail.spotlightReadingLines
            var parts: [String] = []
            if let on = readings.on { parts.append("on \(on)") }
            if let kun = readings.kun { parts.append("kun \(kun)") }
            let readingSummary = parts.isEmpty ? "—" : parts.joined(separator: " · ")
            configuration.secondaryText = "\(subject.meaningSummary) · \(readingSummary)"
            configuration.secondaryTextProperties.color = .secondaryLabel
            configuration.secondaryTextProperties.numberOfLines = 2
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

    private func loadSeedKanji() {
        isLoadingSeed = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let details = KanjidicStore.shared.popularKanji(limit: 80)
            let seeded = details.map(KanjiSpotlightSubject.make(from:))
            await MainActor.run {
                guard let self else { return }
                self.isLoadingSeed = false
                self.subjects = seeded
                self.collectionView.reloadData()
            }
        }
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadSeedKanji()
            return
        }
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let details = KanjidicStore.shared.searchKanji(query: trimmed, limit: 60)
            let found = details.map(KanjiSpotlightSubject.make(from:))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.subjects = found
                self.collectionView.reloadData()
            }
        }
    }
}

// MARK: - UISearchResultsUpdating

extension KanjiSpotlightListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        runSearch(searchController.searchBar.text ?? "")
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension KanjiSpotlightListViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        subjects.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration,
            for: indexPath,
            item: subjects[indexPath.item]
        )
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let subject = subjects[indexPath.item]
        navigationController?.pushViewController(
            KanjiSpotlightCuratorViewController(subject: subject),
            animated: true
        )
    }
}
