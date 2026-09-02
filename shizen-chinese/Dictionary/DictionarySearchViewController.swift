//
//  DictionarySearchViewController.swift
//  shizen-chinese
//
//  Standalone dictionary search: FTS5-powered live results over simplified CEDICT.
//

import UIKit

final class DictionarySearchViewController: UIViewController {

    private let searchController = UISearchController(searchResultsController: nil)
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var results: [CedictEntry] = []
    private var recentSearches: [String] = []
    private var searchTask: Task<Void, Never>?

    private var isShowingRecents: Bool {
        let query = (searchController.searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty && !recentSearches.isEmpty
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        view.backgroundColor = .systemBackground

        recentSearches = RecentDictionarySearchesStore.load()
        setupNavigationBar()
        setupSearchController()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recentSearches = RecentDictionarySearchesStore.load()
        if isShowingRecents {
            tableView.reloadData()
        }
    }

    @objc private func dismissTapped() {
        view.endEditing(true)
        searchController.isActive = false
        (navigationController ?? self).dismiss(animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async {
            self.searchController.searchBar.becomeFirstResponder()
        }
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(dismissTapped)
        )
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = "Search hanzi, pinyin, or English…"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DictionaryResultCell.self, forCellReuseIdentifier: DictionaryResultCell.reuseId)
        tableView.register(DictionaryRecentSearchCell.self, forCellReuseIdentifier: DictionaryRecentSearchCell.reuseId)
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            recentSearches = RecentDictionarySearchesStore.load()
            tableView.reloadData()
            return
        }
        searchTask = Task { [weak self] in
            let found = CedictStore.shared.search(query: trimmed)
            guard !Task.isCancelled else { return }
            self?.results = found
            self?.tableView.reloadData()
        }
    }

    private func applyRecentSearch(_ query: String) {
        RecentDictionarySearchesStore.record(query)
        recentSearches = RecentDictionarySearchesStore.load()
        searchController.searchBar.text = query
        runSearch(query)
    }

    private func recordCurrentQueryIfNeeded() {
        let trimmed = (searchController.searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        RecentDictionarySearchesStore.record(trimmed)
        recentSearches = RecentDictionarySearchesStore.load()
    }
}

extension DictionarySearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        runSearch(searchController.searchBar.text ?? "")
    }
}

extension DictionarySearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isShowingRecents {
            return recentSearches.count
        }
        return results.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isShowingRecents ? "Recent" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isShowingRecents {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DictionaryRecentSearchCell.reuseId,
                for: indexPath
            ) as! DictionaryRecentSearchCell
            cell.configure(query: recentSearches[indexPath.row])
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: DictionaryResultCell.reuseId, for: indexPath) as! DictionaryResultCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isShowingRecents {
            applyRecentSearch(recentSearches[indexPath.row])
            return
        }
        recordCurrentQueryIfNeeded()
        let detail = WordDictionaryDetailViewController(surface: results[indexPath.row].simplified)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard isShowingRecents else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            let query = self.recentSearches[indexPath.row]
            RecentDictionarySearchesStore.remove(query)
            self.recentSearches = RecentDictionarySearchesStore.load()
            if self.recentSearches.isEmpty {
                tableView.reloadData()
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

private final class DictionaryResultCell: UITableViewCell {
    static let reuseId = "DictionaryResultCell"

    private let expressionLabel = UILabel()
    private let readingLabel = UILabel()
    private let glossLabel = UILabel()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        expressionLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        expressionLabel.textColor = .label
        expressionLabel.setContentHuggingPriority(.required, for: .horizontal)
        expressionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        readingLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        readingLabel.textColor = .secondaryLabel
        readingLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [expressionLabel, readingLabel])
        topRow.axis = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 8

        glossLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        glossLabel.textColor = .secondaryLabel
        glossLabel.numberOfLines = 2

        stack.axis = .vertical
        stack.spacing = 2
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(glossLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with entry: CedictEntry) {
        expressionLabel.text = entry.simplified
        readingLabel.text = entry.pinyinMarked
        readingLabel.isHidden = entry.pinyinMarked.isEmpty
        glossLabel.text = entry.primaryGloss
    }
}

private final class DictionaryRecentSearchCell: UITableViewCell {
    static let reuseId = "DictionaryRecentSearchCell"

    private let iconView = UIImageView()
    private let queryLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "clock.arrow.circlepath")
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        queryLabel.font = UIFont.preferredFont(forTextStyle: .body)
        queryLabel.textColor = .label
        queryLabel.numberOfLines = 1

        contentView.addSubview(iconView)
        contentView.addSubview(queryLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            queryLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            queryLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            queryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            queryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(query: String) {
        queryLabel.text = query
    }
}
