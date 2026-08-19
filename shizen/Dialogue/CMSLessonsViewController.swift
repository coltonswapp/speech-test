//
//  CMSLessonsViewController.swift
//  shizen
//
//  Fetches dialogue lessons from the CMS and displays them grouped by
//  curriculum unit, each section using the same waterfall card grid as
//  DialogueHomeViewController.
//

import UIKit

final class CMSLessonsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private var sectionGridControllers: [LessonWaterfallGridController] = []
    private var sectionViews: [UIView] = []

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

    private func configureHeader() {
        let header = makeSectionHeader(
            title: "Lessons",
            subtitle: "Fetched from the Content Studio CMS"
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

    // MARK: - Sections

    private func renderSections(_ sections: [LessonUnitSection]) {
        for view in sectionViews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        sectionViews = []
        sectionGridControllers = []

        for section in sections {
            if let title = section.title {
                // Extra breathing room between the previous section and this header.
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
            renderSections([])
            return
        }

        ContentCMSClient.fetchDialogueLessonIndex { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let index):
                    let sections = LessonUnitSectionBuilder.sections(from: index)
                    self.renderSections(sections)
                    if index.lessons.isEmpty {
                        self.statusLabel.isHidden = false
                        self.statusLabel.text = "No lessons in CMS yet"
                    } else {
                        self.statusLabel.isHidden = true
                        self.statusLabel.text = nil
                    }
                case .failure(let error):
                    self.renderSections([])
                    self.statusLabel.isHidden = false
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func openLesson(_ lesson: WaterfallLesson) {
        guard let id = lesson.id else { return }
        let picker = LessonScenarioPickerViewController(collectionID: id, fallbackTitle: lesson.title)
        navigationController?.pushViewController(picker, animated: true)
    }
}
