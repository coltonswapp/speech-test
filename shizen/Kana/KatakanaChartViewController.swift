//
//  KatakanaChartViewController.swift
//  shizen
//
//  Scrollable manual-layout reference chart (DEBUG).


import UIKit

final class KatakanaChartViewController: UIViewController {

    private let scrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Katakana chart"
        navigationItem.largeTitleDisplayMode = .never

        let onKanaSelected: (String, String) -> Void = { [weak self] kana, romaji in
            let detail = KanaDetailViewController(kana: kana, romaji: romaji)
            self?.navigationController?.pushViewController(detail, animated: true)
        }

        let seionChart = KatakanaGridChartView(kind: .seion, onKanaSelected: onKanaSelected)
        let voicedChart = KatakanaGridChartView(kind: .voiced, onKanaSelected: onKanaSelected)
        let yoonChart = KatakanaGridChartView(kind: .yoon, onKanaSelected: onKanaSelected)

        func makeCaption(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            return label
        }

        let voicedCaption = makeCaption(
            "Voiced & semi-voiced (\u{FF9E} dakuten · \u{FF9F} handakuten)"
        )
        let yoonCaption = makeCaption(
            "Yōon (\u{30E3} · \u{30E5} · \u{30E7}) — katakana with small ya · yu · yo sounds"
        )

        let contentStack = UIStackView(arrangedSubviews: [
            seionChart, voicedCaption, voicedChart, yoonCaption, yoonChart,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setCustomSpacing(28, after: seionChart)
        contentStack.setCustomSpacing(28, after: voicedChart)

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.semanticContentAttribute = .forceLeftToRight

        contentStack.semanticContentAttribute = .forceLeftToRight
        for sub in [seionChart, voicedChart, yoonChart] {
            sub.semanticContentAttribute = .forceLeftToRight
        }

        view.backgroundColor = ExperimentPalette.pageBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -inset),
        ])
    }
}
