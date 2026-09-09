//
//  LemmaResolutionExperimentViewController.swift
//  shizen
//
//  Regression gallery for verb-form → lemma / kana / romaji resolution.
//

import UIKit

final class LemmaResolutionExperimentViewController: UIViewController {

    private enum Filter: Int, CaseIterable {
        case all
        case failing

        var title: String {
            switch self {
            case .all: return "All"
            case .failing: return "Failing"
            }
        }
    }

    private struct Fixture: Hashable {
        let surface: String
        let expectedLemma: String
        let expectedReading: String
        let note: String
    }

    private struct Section: Hashable {
        let title: String
        let fixtures: [Fixture]
    }

    private struct EvaluatedRow: Hashable {
        let fixture: Fixture
        let lemma: String?
        let reading: String
        let romaji: String

        var lemmaPasses: Bool { lemma == fixture.expectedLemma }
        var readingPasses: Bool { reading == fixture.expectedReading }
        var passes: Bool { lemmaPasses && readingPasses }
    }

    private static let catalog: [Section] = [
        Section(title: "Godan す · 探す", fixtures: [
            Fixture(surface: "探す", expectedLemma: "探す", expectedReading: "さがす", note: "dictionary form"),
            Fixture(surface: "探して", expectedLemma: "探す", expectedReading: "さがして", note: "te-form"),
            Fixture(surface: "探します", expectedLemma: "探す", expectedReading: "さがします", note: "polite"),
            Fixture(surface: "探してます", expectedLemma: "探す", expectedReading: "さがしてます", note: "てます contraction"),
            Fixture(surface: "探してる", expectedLemma: "探す", expectedReading: "さがしてる", note: "てる contraction"),
            Fixture(surface: "探してた", expectedLemma: "探す", expectedReading: "さがしてた", note: "てた contraction"),
            Fixture(surface: "探してました", expectedLemma: "探す", expectedReading: "さがしてました", note: "てました"),
            Fixture(surface: "探しています", expectedLemma: "探す", expectedReading: "さがしています", note: "full ています"),
            Fixture(surface: "探さない", expectedLemma: "探す", expectedReading: "さがさない", note: "negative"),
            Fixture(surface: "探そう", expectedLemma: "探す", expectedReading: "さがそう", note: "volitional"),
            Fixture(surface: "探した", expectedLemma: "探す", expectedReading: "さがした", note: "plain past"),
        ]),
        Section(title: "Godan te-forms", fixtures: [
            Fixture(surface: "話してます", expectedLemma: "話す", expectedReading: "はなしてます", note: "す · てます"),
            Fixture(surface: "歩いて", expectedLemma: "歩く", expectedReading: "あるいて", note: "く · いて"),
            Fixture(surface: "歩いてます", expectedLemma: "歩く", expectedReading: "あるいてます", note: "く · てます"),
            Fixture(surface: "歩きます", expectedLemma: "歩く", expectedReading: "あるきます", note: "く · ます"),
            Fixture(surface: "泳いで", expectedLemma: "泳ぐ", expectedReading: "およいで", note: "ぐ · いで"),
            Fixture(surface: "泳いでます", expectedLemma: "泳ぐ", expectedReading: "およいでます", note: "ぐ · でます"),
            Fixture(surface: "待って", expectedLemma: "待つ", expectedReading: "まって", note: "つ · って"),
            Fixture(surface: "待ってます", expectedLemma: "待つ", expectedReading: "まってます", note: "つ · てます"),
            Fixture(surface: "買って", expectedLemma: "買う", expectedReading: "かって", note: "う · って"),
            Fixture(surface: "やってます", expectedLemma: "やる", expectedReading: "やってます", note: "る · てます"),
            Fixture(surface: "飲んで", expectedLemma: "飲む", expectedReading: "のんで", note: "む · んで"),
            Fixture(surface: "飲んでます", expectedLemma: "飲む", expectedReading: "のんでます", note: "む · でます"),
            Fixture(surface: "行って", expectedLemma: "行く", expectedReading: "いって", note: "行く te-form"),
            Fixture(surface: "行ってます", expectedLemma: "行く", expectedReading: "いってます", note: "行く てます"),
        ]),
        Section(title: "Ichidan", fixtures: [
            Fixture(surface: "食べる", expectedLemma: "食べる", expectedReading: "たべる", note: "dictionary form"),
            Fixture(surface: "食べて", expectedLemma: "食べる", expectedReading: "たべて", note: "te-form"),
            Fixture(surface: "食べます", expectedLemma: "食べる", expectedReading: "たべます", note: "polite"),
            Fixture(surface: "食べてます", expectedLemma: "食べる", expectedReading: "たべてます", note: "てます"),
            Fixture(surface: "食べた", expectedLemma: "食べる", expectedReading: "たべた", note: "plain past"),
            Fixture(surface: "見てます", expectedLemma: "見る", expectedReading: "みてます", note: "見る てます"),
            Fixture(surface: "見てる", expectedLemma: "見る", expectedReading: "みてる", note: "見る てる"),
        ]),
        Section(title: "する verbs", fixtures: [
            Fixture(surface: "してます", expectedLemma: "する", expectedReading: "してます", note: "する てます"),
            Fixture(surface: "しています", expectedLemma: "する", expectedReading: "しています", note: "する ています"),
            Fixture(surface: "勉強してます", expectedLemma: "勉強する", expectedReading: "べんきょうしてます", note: "vs てます"),
            Fixture(surface: "勉強しています", expectedLemma: "勉強する", expectedReading: "べんきょうしています", note: "vs ています"),
        ]),
        Section(title: "連用形 + そう", fixtures: [
            Fixture(surface: "遅れそう", expectedLemma: "遅れる", expectedReading: "おくれそう", note: "ichidan stem + そう"),
            Fixture(surface: "食べそう", expectedLemma: "食べる", expectedReading: "たべそう", note: "ichidan stem + そう"),
            Fixture(surface: "書きそう", expectedLemma: "書く", expectedReading: "かきそう", note: "godan stem + そう"),
            Fixture(surface: "見たい", expectedLemma: "見る", expectedReading: "みたい", note: "ichidan + たい"),
        ]),
    ]

    private var filter: Filter = .all
    private var evaluated: [[EvaluatedRow]] = []
    private var visibleSections: [(title: String, rows: [EvaluatedRow])] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let tryField = UITextField()
    private let tryResultLabel = UILabel()
    private let summaryLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lemma resolution"
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.clipboard"),
            style: .plain,
            target: self,
            action: #selector(copyFailuresTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Copy failures"

        evaluateCatalog()
        setupTable()
        reloadVisible()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        evaluateCatalog()
        reloadVisible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        relayoutHeader()
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = ExperimentPalette.pageBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.tableHeaderView = makeHeader()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeHeader() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        filterControl.selectedSegmentIndex = Filter.all.rawValue
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)

        tryField.placeholder = "Try a form, e.g. 探してます"
        tryField.borderStyle = .roundedRect
        tryField.font = .preferredFont(forTextStyle: .body)
        tryField.autocorrectionType = .no
        tryField.spellCheckingType = .no
        tryField.returnKeyType = .done
        tryField.clearButtonMode = .whileEditing
        tryField.delegate = self
        tryField.addTarget(self, action: #selector(tryFieldChanged), for: .editingChanged)

        tryResultLabel.font = .preferredFont(forTextStyle: .footnote)
        tryResultLabel.textColor = .secondaryLabel
        tryResultLabel.numberOfLines = 0
        tryResultLabel.isHidden = true

        stack.addArrangedSubview(summaryLabel)
        stack.addArrangedSubview(filterControl)
        stack.addArrangedSubview(tryField)
        stack.addArrangedSubview(tryResultLabel)

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
        ])

        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        header.frame = CGRect(origin: .zero, size: size)
        return header
    }

    private func evaluateCatalog() {
        evaluated = Self.catalog.map { section in
            section.fixtures.map(Self.evaluate)
        }
    }

    private static func evaluate(_ fixture: Fixture) -> EvaluatedRow {
        let lookup = JMDictStore.shared.lookup(forSurface: fixture.surface)
        let reading = JMDictStore.shared.kanaReadingForDisplay(surface: fixture.surface, matching: lookup.primaryEntry)
        let romaji = JMDictStore.shared.romajiForDisplay(surface: fixture.surface, matching: lookup.primaryEntry)
        return EvaluatedRow(
            fixture: fixture,
            lemma: lookup.resolvedLemma,
            reading: reading,
            romaji: romaji
        )
    }

    private func reloadVisible() {
        let allRows = evaluated.flatMap { $0 }
        let passing = allRows.filter(\.passes).count
        summaryLabel.text = "\(passing) / \(allRows.count) passing · green is lemma + kana reading vs the fixture. Tap a row for the dictionary sheet. Clipboard button prints failures to the console."

        visibleSections = zip(Self.catalog, evaluated).compactMap { section, rows in
            let filtered = filter == .failing ? rows.filter { !$0.passes } : rows
            guard !filtered.isEmpty else { return nil }
            return (section.title, filtered)
        }

        if let header = tableView.tableHeaderView {
            let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
            let size = header.systemLayoutSizeFitting(
                CGSize(width: width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            if header.frame.size != size {
                header.frame.size = size
                tableView.tableHeaderView = header
            }
        }
        tableView.reloadData()
    }

    @objc private func copyFailuresTapped() {
        let report = failureReport()
        print(report)
        UIPasteboard.general.string = report
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func failureReport() -> String {
        let failures = zip(Self.catalog, evaluated).compactMap { section, rows -> (String, [EvaluatedRow])? in
            let failed = rows.filter { !$0.passes }
            guard !failed.isEmpty else { return nil }
            return (section.title, failed)
        }
        let total = evaluated.flatMap { $0 }.count
        let failCount = failures.reduce(0) { $0 + $1.1.count }

        var lines: [String] = [
            "Lemma resolution failures (\(failCount)/\(total))",
            "",
        ]

        if failCount == 0 {
            lines.append("None.")
            return lines.joined(separator: "\n")
        }

        for (sectionTitle, rows) in failures {
            lines.append(sectionTitle)
            for row in rows {
                var mismatch: [String] = []
                if !row.lemmaPasses {
                    mismatch.append("lemma \(row.lemma ?? "—") (expected \(row.fixture.expectedLemma))")
                }
                if !row.readingPasses {
                    mismatch.append("reading \(row.reading) (expected \(row.fixture.expectedReading))")
                }
                lines.append("- \(row.fixture.surface) · \(row.fixture.note)")
                lines.append("  \(mismatch.joined(separator: " · "))")
                if !row.romaji.isEmpty {
                    lines.append("  romaji \(row.romaji)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        reloadVisible()
    }

    @objc private func tryFieldChanged() {
        let surface = tryField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !surface.isEmpty else {
            tryResultLabel.text = nil
            tryResultLabel.isHidden = true
            relayoutHeader()
            return
        }

        let lookup = JMDictStore.shared.lookup(forSurface: surface)
        let lemma = lookup.resolvedLemma ?? "—"
        let reading = JMDictStore.shared.kanaReadingForDisplay(surface: surface, matching: lookup.primaryEntry)
        let romaji = JMDictStore.shared.romajiForDisplay(surface: surface, matching: lookup.primaryEntry)
        tryResultLabel.text = "\(surface) → \(lemma)\n\(reading) · \(romaji.isEmpty ? "—" : romaji)"
        tryResultLabel.isHidden = false
        relayoutHeader()
    }

    private func relayoutHeader() {
        guard let header = tableView.tableHeaderView else { return }
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        guard width > 0 else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        guard header.frame.width != width || header.frame.height != size.height else { return }
        header.frame.size = CGSize(width: width, height: size.height)
        tableView.tableHeaderView = header
    }
}

extension LemmaResolutionExperimentViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleSections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let block = visibleSections[section]
        let failed = block.rows.filter { !$0.passes }.count
        if failed == 0 {
            return "\(block.title) · \(block.rows.count)"
        }
        return "\(block.title) · \(block.rows.count - failed)/\(block.rows.count)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = "\(row.fixture.surface)  →  \(row.lemma ?? "—")"
        content.textProperties.font = .preferredFont(forTextStyle: .headline)

        var lines: [String] = []
        let romajiLine = row.romaji.isEmpty ? row.reading : "\(row.reading) · \(row.romaji)"
        lines.append(romajiLine)
        lines.append(row.fixture.note)

        if !row.passes {
            if !row.lemmaPasses {
                lines.append("expected lemma \(row.fixture.expectedLemma)")
            }
            if !row.readingPasses {
                lines.append("expected reading \(row.fixture.expectedReading)")
            }
        }

        content.secondaryText = lines.joined(separator: "\n")
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content

        let symbol = row.passes ? "checkmark.circle.fill" : "xmark.circle.fill"
        let color: UIColor = row.passes ? .systemGreen : .systemRed
        let image = UIImage(systemName: symbol)?.withTintColor(color, renderingMode: .alwaysOriginal)
        cell.accessoryView = UIImageView(image: image)
        cell.backgroundColor = ExperimentPalette.cardSurface
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let surface = visibleSections[indexPath.section].rows[indexPath.row].fixture.surface
        WordDictionaryDetailSheetPresenter.push(surface: surface, from: self)
    }
}

extension LemmaResolutionExperimentViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
