//
//  SettingsDetailListViewController.swift
//  shizen
//
//  Plain inset-grouped list pushed from a settings row.
//

import UIKit

final class SettingsDetailListViewController: UIViewController {
    private let screenTitle: String
    private let makeItems: () -> [SettingsMenuItem]
    var onSelect: ((SettingsMenuItem, UIView) -> Void)?

    private var items: [SettingsMenuItem] = []
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, SettingsMenuItem>!

    init(title: String, makeItems: @escaping () -> [SettingsMenuItem]) {
        self.screenTitle = title
        self.makeItems = makeItems
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func reload() {
        guard dataSource != nil else { return }
        items = makeItems()
        var snapshot = NSDiffableDataSourceSnapshot<Int, SettingsMenuItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func configureCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SettingsMenuItem> {
            cell, _, item in
            SettingsMenuStyle.apply(
                to: cell,
                title: item.title,
                subtitle: item.subtitle,
                symbolName: item.symbolName,
                accessories: [.disclosureIndicator()]
            )
        }

        dataSource = UICollectionViewDiffableDataSource<Int, SettingsMenuItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }
}

extension SettingsDetailListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let source = collectionView.cellForItem(at: indexPath) ?? collectionView
        onSelect?(item, source)
    }
}
