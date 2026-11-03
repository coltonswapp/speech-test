//
//  UserProfileViewController.swift
//  shizen
//
//  Signed-in account: identity, progress stats, plan, and log out.
//

import UIKit

final class UserProfileViewController: UIViewController {

    private nonisolated enum Section: Hashable, Sendable {
        case account
        case progress
        case levels
        case membership
        case logOut
        case hana

        var title: String? {
            switch self {
            case .account: return "Account"
            case .progress: return "Progress"
            case .levels: return "Levels"
            case .membership: return "Membership"
            case .logOut, .hana: return nil
            }
        }
    }

    private nonisolated enum Item: Hashable, Sendable {
        case identity(title: String, subtitle: String)
        case stats(stars: Int, scenes: Int, days: Int?)
        case level(Int, completed: Int, total: Int, stars: Int)
        case plan(isPro: Bool)
        case logOut
        case hana
    }

    /// Cell margin (16), extra row inset, badge (44) and gap (14), so level separators start under the text.
    private static let levelSeparatorInset: CGFloat = 16 + ProfileProgressStyle.levelRowExtraInset + 44 + 14

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(progressDidChange),
            name: DialogueProgressStore.didChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authUserDidChange),
            name: AuthService.userDidChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySnapshot()
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let sectionID = self?.dataSource?.sectionIdentifier(for: index)
            let hasHeader = sectionID?.title != nil
            config.headerMode = hasHeader ? .supplementary : .none
            switch sectionID {
            case .progress, .hana:
                config.backgroundColor = .clear
                config.showsSeparators = false
            case .levels:
                config.itemSeparatorHandler = { _, separator in
                    var separator = separator
                    separator.topSeparatorInsets.leading = Self.levelSeparatorInset
                    separator.bottomSeparatorInsets.leading = Self.levelSeparatorInset
                    return separator
                }
            default:
                break
            }
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
            guard hasHeader else { return section }
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(32)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }

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
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            self?.configure(cell: cell, for: item)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<SettingsSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let title = self?.dataSource.sectionIdentifier(for: indexPath.section)?.title else { return }
            header.configure(title: title)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func configure(cell: UICollectionViewListCell, for item: Item) {
        switch item {
        case .identity(let title, let subtitle):
            SettingsMenuStyle.apply(
                to: cell,
                title: title,
                subtitle: subtitle,
                symbolName: "person.crop.circle",
                accessories: []
            )

        case .stats(let stars, let scenes, let days):
            cell.contentConfiguration = ProfileStatsContentConfiguration(
                stars: stars,
                scenesCompleted: scenes,
                daysSinceJoining: days
            )
            cell.accessories = []
            cell.backgroundConfiguration = .clear()

        case .level(let level, let completed, let total, let stars):
            cell.contentConfiguration = ProfileLevelContentConfiguration(
                level: level,
                completed: completed,
                total: total,
                stars: stars
            )
            cell.accessories = []
            cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()

        case .plan(let isPro):
            SettingsMenuStyle.apply(
                to: cell,
                title: "Plan",
                subtitle: isPro ? nil : "Pro is coming soon",
                symbolName: "crown",
                accessories: [.label(text: isPro ? "Pro" : "Free")]
            )

        case .logOut:
            SettingsMenuStyle.apply(
                to: cell,
                title: "Log Out",
                subtitle: nil,
                symbolName: "rectangle.portrait.and.arrow.right",
                accessories: []
            )
            if var content = cell.contentConfiguration as? UIListContentConfiguration {
                content.textProperties.color = .systemRed
                content.imageProperties.tintColor = .systemRed
                cell.contentConfiguration = content
            }

        case .hana:
            cell.contentConfiguration = ProfileHanaContentConfiguration()
            cell.accessories = []
            cell.backgroundConfiguration = .clear()
        }
    }

    private func applySnapshot() {
        guard dataSource != nil else { return }
        let account = AuthService.shared.account

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let levels = levelItems()
        snapshot.appendSections(
            levels.isEmpty
                ? [.account, .progress, .membership, .logOut, .hana]
                : [.account, .progress, .levels, .membership, .logOut, .hana]
        )
        snapshot.appendItems([.identity(title: account.title, subtitle: account.subtitle)], toSection: .account)

        let joined = UserProfileStore.shared.profile?.createdAt ?? AuthService.shared.accountCreationDate
        let scenes = levels.reduce(0) { total, item in
            guard case .level(_, let completed, _, _) = item else { return total }
            return total + completed
        }
        snapshot.appendItems([.stats(
            stars: DialogueProgressStore.shared.totalDisplayedStarCount(),
            scenes: scenes,
            days: joined.map { Self.daysSince($0) }
        )], toSection: .progress)
        if !levels.isEmpty {
            snapshot.appendItems(levels, toSection: .levels)
        }
        snapshot.appendItems([.plan(isPro: ProMembership.isPro)], toSection: .membership)
        snapshot.appendItems([.logOut], toSection: .logOut)
        snapshot.appendItems([.hana], toSection: .hana)

        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    /// Uses the cached lesson index only. Tracks with no playable scenes are left out.
    private func levelItems() -> [Item] {
        guard let index = ContentCMSClient.cachedDialogueLessonIndex() else { return [] }
        return DialogueLessonTrack.allCases.compactMap { track in
            let progress = LessonUnitSectionBuilder.trackProgress(
                from: index,
                track: track,
                progress: DialogueProgressStore.shared
            )
            guard progress.totalScenes > 0 else { return nil }
            return .level(
                track.rawValue,
                completed: progress.completedScenes,
                total: progress.totalScenes,
                stars: progress.stars
            )
        }
    }

    private static func daysSince(_ date: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(days, 0)
    }

    // MARK: - Updates

    @objc private func progressDidChange() {
        applySnapshot()
    }

    @objc private func authUserDidChange() {
        if AuthService.shared.account.isSignedIn {
            applySnapshot()
        } else {
            popIfVisible()
        }
    }

    private func popIfVisible() {
        guard navigationController?.topViewController === self else { return }
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Log out

    private func confirmLogOut() {
        let alert = UIAlertController(
            title: "Log out?",
            message: "You can sign in again with Apple or Google.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            do {
                try AuthService.shared.signOut()
                self?.popIfVisible()
            } catch {
                let failure = UIAlertController(
                    title: "Couldn’t log out",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                failure.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(failure, animated: true)
            }
        })
        present(alert, animated: true)
    }
}

extension UserProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) == .logOut
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard dataSource.itemIdentifier(for: indexPath) == .logOut else { return }
        confirmLogOut()
    }
}
