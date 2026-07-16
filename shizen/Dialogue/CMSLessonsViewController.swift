//
//  CMSLessonsViewController.swift
//  shizen
//
//  Fetches dialogue lessons from the CMS and displays them in the same
//  waterfall card grid used by DialogueHomeViewController.
//

import UIKit

final class CMSLessonsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let lessonsGridController = LessonWaterfallGridController()
    private var lessonsGridHeightConstraint: NSLayoutConstraint?
    private let statusLabel = UILabel()
    private var lessons: [WaterfallLesson] = []

    private static let horizontalInset: CGFloat = 16

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CMS Lessons"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        configureScrollView()
        configureLessonsSection()
        layoutViews()
        fetchLessons()

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        lessonsGridController.refreshContentHeightIfNeeded()
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
    }

    private func configureLessonsSection() {
        let header = makeSectionHeader(
            title: "Lessons",
            subtitle: "Fetched from the Content Studio CMS"
        )

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "Loading…"

        let collectionView = lessonsGridController.collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isScrollEnabled = false
        collectionView.clipsToBounds = false
        lessonsGridController.onSelect = { [weak self] _, lesson in
            self?.openLesson(lesson)
        }
        lessonsGridController.onContentHeightChanged = { [weak self] height in
            self?.lessonsGridHeightConstraint?.constant = height
        }

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
        contentStack.addArrangedSubview(collectionView)

        let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
        heightConstraint.isActive = true
        lessonsGridHeightConstraint = heightConstraint
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

    // MARK: - Data

    @objc private func refreshTapped() {
        fetchLessons()
    }

    private func fetchLessons() {
        statusLabel.isHidden = false
        statusLabel.text = ContentCMSClient.isConfigured
            ? "Loading…"
            : "CMS not configured — set SHIZEN_CMS_BASE_URL"
        navigationItem.rightBarButtonItem?.isEnabled = false

        guard ContentCMSClient.isConfigured else {
            lessons = []
            lessonsGridController.setLessons([])
            return
        }

        ContentCMSClient.fetchDialogueLessons { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let summaries):
                    self.lessons = summaries.map { summary in
                        WaterfallLesson(
                            id: summary.id,
                            title: summary.title,
                            conversationCount: summary.scenarioCount,
                            thumbnailName: summary.sceneImage ?? summary.id,
                            thumbnailURL: summary.thumbnailUrl.flatMap(URL.init(string:)),
                            isLocked: false
                        )
                    }
                    self.lessonsGridController.setLessons(self.lessons)
                    if summaries.isEmpty {
                        self.statusLabel.isHidden = false
                        self.statusLabel.text = "No lessons in CMS yet"
                    } else {
                        self.statusLabel.isHidden = true
                        self.statusLabel.text = nil
                    }
                case .failure(let error):
                    self.lessons = []
                    self.lessonsGridController.setLessons([])
                    self.statusLabel.isHidden = false
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func openLesson(_ lesson: WaterfallLesson) {
        guard let id = lesson.id else { return }
        let dialogue = DialogueNestedPagingExperimentViewController(collectionID: id)
        navigationController?.pushViewController(dialogue, animated: true)
    }
}
