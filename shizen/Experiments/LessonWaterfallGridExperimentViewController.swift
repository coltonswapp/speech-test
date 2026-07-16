//
//  LessonWaterfallGridExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: waterfall cascade grid where each cell is a lesson thumbnail card.
//  Locked lessons show a yellow-tinted liquid glass lock badge in the top-right corner.
//  Grid/cell/layout types live in Dialogue/LessonWaterfallGrid.swift and are shared
//  with the production Dialogue screen.
//

import UIKit

final class LessonWaterfallGridExperimentViewController: UIViewController {

    private let gridController = LessonWaterfallGridController()

    private let lessons: [WaterfallLesson] = [
        WaterfallLesson(
            title: "At the Train Station",
            conversationCount: 5,
            thumbnailName: "train-station",
            isLocked: false
        ),
        WaterfallLesson(
            title: "At the Library",
            conversationCount: 5,
            thumbnailName: "at-the-library",
            isLocked: false
        ),
        WaterfallLesson(
            title: "At the Convenient Store",
            conversationCount: 5,
            thumbnailName: "at-the-convenient-store",
            isLocked: true
        ),
        WaterfallLesson(
            title: "Asking Directions",
            conversationCount: 5,
            thumbnailName: "asking-directions",
            isLocked: true
        ),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lesson waterfall grid"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        gridController.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collectionView = gridController.collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.alwaysBounceVertical = true

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        gridController.setLessons(lessons)
    }
}
