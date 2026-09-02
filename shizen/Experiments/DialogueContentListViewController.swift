//
//  DialogueContentListViewController.swift
//  shizen
//
//  Lesson waterfall for Dialogue Replay. Opens a scenario picker, then a
//  format chooser, instead of the nested paging lesson player.
//

import UIKit

final class DialogueContentListViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private var sectionGridControllers: [LessonWaterfallGridController] = []
    private var sectionViews: [UIView] = []

    private static let horizontalInset: CGFloat = 16

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dialogue Replay"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        configureScrollView()
        configureHeader()
        layoutViews()
        fetchLessons()

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for controller in sectionGridControllers {
            controller.refreshContentHeightIfNeeded()
        }
    }

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
    }

    private func configureHeader() {
        let header = makeSectionHeader(
            title: "Lessons",
            subtitle: "Pick a dialogue to replay"
        )

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "Loading…"

        let statusWrap = UIView()
        statusWrap.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusWrap.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: statusWrap.topAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusWrap.leadingAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(equalTo: statusWrap.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: statusWrap.bottomAnchor),
        ])

        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(statusWrap)
    }

    private func layoutViews() {
        view.addSubview(scrollView)
        let inset = Self.horizontalInset
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 16
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -24
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: inset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -inset
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -inset * 2
            ),
        ])
    }

    private func makeSectionHeader(title: String, subtitle: String?) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        var arrangedSubviews: [UIView] = [titleLabel]
        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 0
            arrangedSubviews.append(subtitleLabel)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 18,
            bottom: 0,
            trailing: 0
        )
        return stack
    }

    private func renderSections(_ sections: [LessonUnitSection]) {
        for view in sectionViews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        sectionViews = []
        sectionGridControllers = []

        for section in sections {
            if let title = section.title {
                if let previous = sectionViews.last {
                    contentStack.setCustomSpacing(24, after: previous)
                }
                let header = makeSectionHeader(title: title, subtitle: section.subtitle)
                contentStack.addArrangedSubview(header)
                sectionViews.append(header)
            }

            let gridController = LessonWaterfallGridController()
            let collectionView = gridController.collectionView
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.isScrollEnabled = false
            collectionView.clipsToBounds = false

            let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
            heightConstraint.isActive = true
            gridController.onContentHeightChanged = { height in
                heightConstraint.constant = height
            }
            gridController.onSelect = { [weak self] _, lesson in
                self?.openLesson(lesson)
            }

            contentStack.addArrangedSubview(collectionView)
            sectionViews.append(collectionView)
            sectionGridControllers.append(gridController)
            gridController.setLessons(section.lessons)
        }
    }

    @objc private func refreshTapped() {
        fetchLessons()
    }

    private func fetchLessons() {
        statusLabel.isHidden = false
        statusLabel.text = ContentCMSClient.isConfigured ? "Loading…" : "CMS not configured — bundled lessons"
        navigationItem.rightBarButtonItem?.isEnabled = false

        guard ContentCMSClient.isConfigured else {
            navigationItem.rightBarButtonItem?.isEnabled = true
            renderBundledFallback()
            return
        }

        ContentCMSClient.fetchDialogueLessonIndex { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let index):
                    let sections = LessonUnitSectionBuilder.sections(from: index)
                    if sections.isEmpty {
                        self.statusLabel.text = "No lessons in CMS yet — showing bundled"
                        self.renderBundledFallback()
                    } else {
                        self.renderSections(sections)
                        self.statusLabel.isHidden = true
                        self.statusLabel.text = nil
                    }
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                    self.renderBundledFallback()
                }
            }
        }
    }

    private func renderBundledFallback() {
        let lessons = DialogueScenarioCollectionCatalog.allCollections.map { collection in
            WaterfallLesson(
                id: collection.id,
                title: collection.title,
                conversationCount: collection.scenarios.count,
                thumbnailName: collection.sceneImageName ?? collection.id,
                thumbnailURL: collection.thumbnailURL,
                isLocked: false
            )
        }
        guard !lessons.isEmpty else {
            renderSections([])
            statusLabel.isHidden = false
            if statusLabel.text?.isEmpty != false {
                statusLabel.text = "No bundled lessons found"
            }
            return
        }
        renderSections([
            LessonUnitSection(
                title: "Bundled lessons",
                subtitle: nil,
                lessons: lessons
            ),
        ])
        statusLabel.isHidden = statusLabel.text == nil
    }

    private func openLesson(_ lesson: WaterfallLesson) {
        guard let id = lesson.id else { return }
        let picker = LessonScenarioPickerViewController(collectionID: id, fallbackTitle: lesson.title)
        picker.onOpenScenario = { [weak self] collection, scenarioID in
            guard let self,
                  let scenario = collection.scenarios.first(where: { $0.id == scenarioID })
            else { return }
            let formatPicker = DialogueContentFormatPickerViewController(
                collection: collection,
                scenario: scenario
            )
            self.navigationController?.pushViewController(formatPicker, animated: true)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

// MARK: - Format picker

final class DialogueContentFormatPickerViewController: UIViewController {

    private let collection: DialogueScenarioCollection
    private let scenario: DialogueScenarioCollection.Scenario
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, DialogueContentFormat>!

    init(collection: DialogueScenarioCollection, scenario: DialogueScenarioCollection.Scenario) {
        self.collection = collection
        self.scenario = scenario
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Format"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DialogueContentFormat> {
            cell, _, format in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = format.title
            content.secondaryText = format.subtitle
            content.image = UIImage(systemName: format.symbolName)
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = self?.scenario.menuTitle
            header.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Int, DialogueContentFormat>(
            collectionView: collectionView
        ) { collectionView, indexPath, format in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: format
            )
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, DialogueContentFormat>()
        snapshot.appendSections([0])
        snapshot.appendItems(DialogueContentFormat.allCases, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension DialogueContentFormatPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let format = dataSource.itemIdentifier(for: indexPath) else { return }
        let picker = DialogueContentLinePickerViewController(
            collection: collection,
            scenario: scenario,
            format: format
        )
        navigationController?.pushViewController(picker, animated: true)
    }
}
