//
//  GrammarLearningFlowViewController.swift
//  shizen
//

import UIKit

final class GrammarLearningFlowViewController: UIViewController, MainTabScrollable {

    var mainTabScrollViews: [UIScrollView] { [scrollView] }

    private let masteryStore: GrammarMasteryStore
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let progressGridCard = GrammarProgressGridCardView()
    private let checkpointsContainer = UIView()
    private var checkpointsViewController: GrammarCheckpointListViewController!
    private var checkpointsHeightConstraint: NSLayoutConstraint?
    private var checkpointsViewConstraints: [NSLayoutConstraint] = []
    private let progressSubtitleLabel = UILabel()
    private var lastLaidOutProgressGridWidth: CGFloat = 0

    private static let horizontalInset: CGFloat = 16

    init(masteryStore: GrammarMasteryStore = .shared) {
        self.masteryStore = masteryStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureScrollView()
        configureCheckpointsSection()
        layoutViews()
        configureProgressGridSelection()
        refreshProgressGrid()
    }

    private func configureProgressGridSelection() {
        progressGridCard.onSelectPoint = { [weak self] point in
            guard let self else { return }
            GrammarReferencePresenter.open(point: point, from: self)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        masteryStore.reload()
        updateProgressSubtitle()
        refreshProgressGrid()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = progressGridCard.bounds.width
        guard width > 0, width != lastLaidOutProgressGridWidth else { return }
        lastLaidOutProgressGridWidth = width
        refreshProgressGrid()
    }

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
    }

    private func configureCheckpointsSection() {
        progressSubtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressSubtitleLabel.textColor = .secondaryLabel
        progressSubtitleLabel.numberOfLines = 0
        updateProgressSubtitle()

        let header = makeSectionHeader(
            title: "JLPT N5 Grammar",
            subtitleView: progressSubtitleLabel
        )

        checkpointsContainer.translatesAutoresizingMaskIntoConstraints = false
        embedCheckpointsList()

        let checkpointsStack = UIStackView(arrangedSubviews: [
            header,
            progressGridCard,
            checkpointsContainer,
        ])
        checkpointsStack.axis = .vertical
        checkpointsStack.spacing = 12
        checkpointsStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(checkpointsStack)

        let height = checkpointsContainer.heightAnchor.constraint(equalToConstant: 1)
        height.isActive = true
        checkpointsHeightConstraint = height
    }

    private func embedCheckpointsList() {
        if let existing = checkpointsViewController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        let child = GrammarCheckpointListViewController(
            masteryStore: masteryStore,
            presentationStyle: .embedded
        )
        child.onEmbeddedHeightChange = { [weak self] height in
            self?.checkpointsHeightConstraint?.constant = max(1, height)
        }
        child.onProgressDidChange = { [weak self] in
            self?.masteryStore.reload()
            self?.updateProgressSubtitle()
            self?.refreshProgressGrid()
        }
        child.onSelectCheckpoint = { [weak self] checkpoint in
            self?.openCheckpoint(checkpoint)
        }

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        checkpointsContainer.addSubview(child.view)
        child.didMove(toParent: self)
        checkpointsViewController = child

        NSLayoutConstraint.deactivate(checkpointsViewConstraints)
        checkpointsViewConstraints = [
            child.view.topAnchor.constraint(equalTo: checkpointsContainer.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: checkpointsContainer.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: checkpointsContainer.leadingAnchor, constant: -Self.horizontalInset),
            child.view.trailingAnchor.constraint(equalTo: checkpointsContainer.trailingAnchor, constant: Self.horizontalInset),
        ]
        NSLayoutConstraint.activate(checkpointsViewConstraints)
    }

    private func openCheckpoint(_ checkpoint: GrammarCheckpoint) {
        let path = GrammarProgressPathViewController(
            masteryStore: masteryStore,
            checkpoint: checkpoint,
            points: GrammarCurriculum.points(for: checkpoint),
            presentationStyle: .standalone
        )
        path.onProgressDidChange = { [weak self] in
            self?.masteryStore.reload()
            self?.updateProgressSubtitle()
            self?.refreshProgressGrid()
            self?.checkpointsViewController?.refreshFromMasteryStore()
        }
        navigationController?.pushViewController(path, animated: true)
    }

    private func layoutViews() {
        view.addSubview(scrollView)
        let inset = Self.horizontalInset
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])
    }

    private func updateProgressSubtitle() {
        let allPoints = GrammarCurriculum.n5Points
        let known = masteryStore.knownCount
        let seen = masteryStore.seenCount
        let total = allPoints.count
        progressSubtitleLabel.text = "\(known) known · \(seen) seen · \(total) patterns"
    }

    private func refreshProgressGrid() {
        let points = GrammarCurriculum.n5Points
        let known = masteryStore.knownCount
        let contentWidth = progressGridCard.bounds.width > 0
            ? progressGridCard.bounds.width
            : view.bounds.width - Self.horizontalInset * 2

        progressGridCard.configure(
            points: points,
            progressLevels: GrammarProgressGridSupport.progressLevels(
                for: points,
                masteryStore: masteryStore
            ),
            title: GrammarProgressGridSupport.cardTitle(
                known: known,
                total: points.count
            ),
            contentWidth: contentWidth
        )
    }

    private func makeSectionHeader(title: String, subtitleView: UIView? = nil) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        var arrangedSubviews: [UIView] = [titleLabel]
        if let subtitleView {
            arrangedSubviews.append(subtitleView)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }
}
