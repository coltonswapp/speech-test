//
//  DialogueLessonWrapUpExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: preview the end-of-lesson wrap-up sheet for any lesson.
//

import UIKit

final class DialogueLessonWrapUpExperimentViewController: UIViewController {

    private enum ScoreSource: CaseIterable {
        case recorded
        case mixed
        case perfect
        case partlyPlayed
        case noScores

        var title: String {
            switch self {
            case .recorded: return "My recorded runs"
            case .mixed: return "Mixed"
            case .perfect: return "Perfect"
            case .partlyPlayed: return "Some scenes unplayed"
            case .noScores: return "Completed, no scores"
            }
        }
    }

    private struct LessonOption: Hashable {
        let id: String
        let title: String
    }

    private var lessons: [LessonOption] = []
    private var selectedLessonID: String?
    private var collection: DialogueScenarioCollection?
    private var scoreSource: ScoreSource = .mixed
    private var isLoadingCollection = false

    private let statusLabel = UILabel()
    private let showButton = PrimaryButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lesson wrap-up"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        showButton.primaryStyle = .yellow
        showButton.setTitle("Show wrap-up", for: .normal)
        showButton.addAction(UIAction { [weak self] _ in
            self?.presentWrapUp()
        }, for: .touchUpInside)

        view.addSubview(statusLabel)
        view.addSubview(showButton)
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            showButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            showButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            showButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            showButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        applyLessons(from: ContentCMSClient.cachedDialogueLessonIndex())
        refresh()
        ContentCMSClient.fetchDialogueLessonIndex { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let index) = result else { return }
                self.applyLessons(from: index)
            }
        }
    }

    private func applyLessons(from index: CMSDialogueLessonIndex?) {
        var options = index?.lessons.map { LessonOption(id: $0.id, title: $0.title) } ?? []
        if options.isEmpty {
            options = DialogueScenarioCollectionCatalog.allCollections.map {
                LessonOption(id: $0.id, title: $0.title)
            }
        }
        lessons = options
        if selectedLessonID == nil || !options.contains(where: { $0.id == selectedLessonID }) {
            let preferred = options.first { $0.title.localizedCaseInsensitiveContains("ball game") } ?? options.first
            if let preferred {
                selectLesson(id: preferred.id)
            }
        }
        refresh()
    }

    private func selectLesson(id: String) {
        selectedLessonID = id
        collection = nil
        isLoadingCollection = true
        refresh()
        DialogueScenarioCollectionCatalog.fetchCollection(id: id) { [weak self] collection in
            DispatchQueue.main.async {
                guard let self, self.selectedLessonID == id else { return }
                self.collection = collection
                self.isLoadingCollection = false
                self.refresh()
            }
        }
    }

    private func refresh() {
        showButton.isEnabled = collection != nil
        if isLoadingCollection {
            statusLabel.text = "Loading lesson…"
        } else if let collection {
            statusLabel.text = "\(collection.title)\n\(collection.scenarios.count) scenes · \(scoreSource.title)"
        } else {
            statusLabel.text = lessons.isEmpty ? "No lessons available" : "Couldn’t load lesson"
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "slider.horizontal.3"),
            primaryAction: nil,
            menu: makeMenu()
        )
    }

    private func makeMenu() -> UIMenu {
        let lessonActions = lessons.map { lesson in
            UIAction(title: lesson.title, state: lesson.id == selectedLessonID ? .on : .off) { [weak self] _ in
                self?.selectLesson(id: lesson.id)
            }
        }
        let scoreActions = ScoreSource.allCases.map { source in
            UIAction(title: source.title, state: source == scoreSource ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.scoreSource = source
                self.refresh()
                self.presentWrapUp()
            }
        }
        return UIMenu(children: [
            UIMenu(title: "Scores", options: [.displayInline, .singleSelection], children: scoreActions),
            UIMenu(title: "Lesson", image: UIImage(systemName: "book"), options: .singleSelection, children: lessonActions),
        ])
    }

    private func presentWrapUp() {
        guard let collection else { return }
        let showSheet = { [weak self] in
            guard let self else { return }
            let summary = self.makeWrapUp(for: collection)
            let sheet = DialogueLessonWrapUpViewController(wrapUp: summary)
            sheet.onBackToLessons = { [weak self] in
                self?.dismiss(animated: true)
            }
            sheet.modalPresentationStyle = UIModalPresentationStyle.pageSheet
            self.present(sheet, animated: true)
        }
        if presentedViewController != nil {
            dismiss(animated: true, completion: showSheet)
        } else {
            showSheet()
        }
    }

    private func makeWrapUp(for collection: DialogueScenarioCollection) -> DialogueLessonWrapUp {
        let recorded = DialogueLessonWrapUp.make(collection: collection)
        guard scoreSource != .recorded else { return recorded }
        let mixed: [(stars: Int, points: Int)] = [(3, 650), (2, 500), (1, 340), (2, 585), (3, 450), (1, 170)]
        let scenes = recorded.scenes.enumerated().map { index, scene -> DialogueLessonWrapUp.Scene in
            let sample = mixed[index % mixed.count]
            switch scoreSource {
            case .recorded:
                return scene
            case .mixed:
                return DialogueLessonWrapUp.Scene(title: scene.title, starCount: sample.stars, points: sample.points)
            case .perfect:
                return DialogueLessonWrapUp.Scene(title: scene.title, starCount: 3, points: 650)
            case .partlyPlayed:
                let played = index % 3 != 2
                return DialogueLessonWrapUp.Scene(
                    title: scene.title,
                    starCount: played ? sample.stars : nil,
                    points: played ? sample.points : nil
                )
            case .noScores:
                return DialogueLessonWrapUp.Scene(title: scene.title, starCount: 1, points: nil)
            }
        }
        return DialogueLessonWrapUp(
            lessonTitle: recorded.lessonTitle,
            thumbnailURL: recorded.thumbnailURL,
            sceneImageName: recorded.sceneImageName,
            totalPossiblePoints: recorded.totalPossiblePoints,
            scenes: scenes
        )
    }
}
