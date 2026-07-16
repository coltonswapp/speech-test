//
//  WordDictionaryDetailViewController.swift
//  shizen
//
//  Half-sheet host for WordDictionaryDetailView.
//

import UIKit

final class WordDictionaryDetailViewController: UIViewController {

    private let surface: String
    private let sentence: String?
    private let scrollView = UIScrollView()
    private let detailView = WordDictionaryDetailView()

    init(surface: String, sentence: String? = nil) {
        self.surface = surface
        self.sentence = sentence
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(detailView)

        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            detailView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: inset),
            detailView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            detailView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            detailView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            detailView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])

        detailView.onSelectCompound = { [weak self] expression in
            self?.presentCompound(expression)
        }
        detailView.onSelectKanji = { [weak self] character in
            self?.presentKanjiDetail(character)
        }

        detailView.configure(surface: surface, sentence: sentence)
    }

    private func presentCompound(_ expression: String) {
        WordDictionaryDetailSheetPresenter.push(surface: expression, from: self)
    }

    private func presentKanjiDetail(_ character: String) {
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kanjiVC = KanjiDetailViewController(character: trimmed)
        if let nav = navigationController {
            nav.pushViewController(kanjiVC, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: kanjiVC)
            kanjiVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(dismissPresentedKanji)
            )
            present(nav, animated: true)
        }
    }

    @objc private func dismissPresentedKanji() {
        presentedViewController?.dismiss(animated: true)
    }
}

enum WordDictionaryDetailSheetPresenter {

    static func present(surface: String, sentence: String? = nil, from viewController: UIViewController, animated: Bool = true) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DefinitionCalloutPresenter.shared.dismiss(animated: true)

        let sheet = WordDictionaryDetailViewController(surface: trimmed, sentence: sentence)
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        viewController.present(sheet, animated: animated)
    }

    /// Pushes the dictionary detail onto the navigation stack instead of
    /// presenting a sheet. Falls back to a wrapped present when there is no
    /// navigation controller. Mirrors the kanji-detail push behavior.
    static func push(surface: String, sentence: String? = nil, from viewController: UIViewController, animated: Bool = true) {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DefinitionCalloutPresenter.shared.dismiss(animated: true)

        let detail = WordDictionaryDetailViewController(surface: trimmed, sentence: sentence)
        if let nav = viewController.navigationController {
            nav.pushViewController(detail, animated: animated)
        } else {
            viewController.present(UINavigationController(rootViewController: detail), animated: animated)
        }
    }
}
