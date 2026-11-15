//
//  DictionaryChecksViewController.swift
//  shizen
//
//  Debug screen: words flagged from a callout (press and hold), then the must-define
//  fixtures with pass/fail against what the token callout would show right now.
//

import UIKit

final class DictionaryChecksViewController: UIViewController {

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

    private struct FixtureRow: Hashable {
        let fixture: DictionaryCheckFixture
        let outcome: DictionaryCalloutOutcome
        var passes: Bool { fixture.passes(outcome) }
    }

    private struct FlagRow: Hashable {
        let flag: DictionaryFlag
        let outcome: DictionaryCalloutOutcome
    }

    private enum Block {
        case flags([FlagRow])
        case fixtures(title: String, rows: [FixtureRow])
    }

    private var filter: Filter = .all
    private var flagRows: [FlagRow] = []
    private var fixtureSections: [(title: String, rows: [FixtureRow])] = []
    private var blocks: [Block] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let summaryLabel = UILabel()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dictionary checks"
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never

        let copy = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.clipboard"),
            style: .plain,
            target: self,
            action: #selector(copyReportTapped)
        )
        copy.accessibilityLabel = "Copy failures and flags"
        navigationItem.rightBarButtonItem = copy

        setupTable()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flagsChanged),
            name: DictionaryFlagStore.didChange,
            object: nil
        )
        evaluate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        evaluate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        relayoutHeader()
    }

    // MARK: - Setup

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = ExperimentPalette.pageBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
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

        stack.addArrangedSubview(summaryLabel)
        stack.addArrangedSubview(filterControl)

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
        ])
        return header
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

    // MARK: - Data

    private func evaluate() {
        flagRows = DictionaryFlagStore.shared.flags.map { flag in
            FlagRow(flag: flag, outcome: .evaluate(surface: flag.surface, sentence: flag.sentence))
        }
        fixtureSections = DictionaryCheckFixture.catalog.map { section in
            (section.title, section.fixtures.map { fixture in
                FixtureRow(fixture: fixture, outcome: .evaluate(surface: fixture.surface, sentence: fixture.sentence))
            })
        }
        reloadVisible()
    }

    private func reloadVisible() {
        let allFixtures = fixtureSections.flatMap(\.rows)
        let passing = allFixtures.filter(\.passes).count
        let flagCount = flagRows.count
        summaryLabel.text = """
            \(passing) / \(allFixtures.count) must-define words pass · \(flagCount) flagged. \
            Press and hold a word's callout in a clip to flag it. Tap a row for the dictionary \
            sheet; swipe a flag to remove it. The clipboard button copies failures and flags.
            """

        var next: [Block] = []
        if !flagRows.isEmpty {
            next.append(.flags(flagRows))
        }
        for section in fixtureSections {
            let rows = filter == .failing ? section.rows.filter { !$0.passes } : section.rows
            guard !rows.isEmpty else { continue }
            next.append(.fixtures(title: section.title, rows: rows))
        }
        blocks = next
        relayoutHeader()
        tableView.reloadData()
    }

    @objc private func flagsChanged() {
        evaluate()
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        reloadVisible()
    }

    // MARK: - Export

    @objc private func copyReportTapped() {
        let report = makeReport()
        print(report)
        UIPasteboard.general.string = report
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Failing fixtures, then flags, then paste-ready `jmdict_supplement.tsv` rows for the flags.
    private func makeReport() -> String {
        var lines: [String] = []
        let failing = fixtureSections.flatMap(\.rows).filter { !$0.passes }
        lines.append("Must-define failures (\(failing.count))")
        if failing.isEmpty { lines.append("None.") }
        for row in failing {
            let expected = row.fixture.expectedHeadword.map { "expected \($0)" } ?? "expected a definition"
            lines.append("- \(row.fixture.surface) · \(expected) · got \(row.outcome.summary)")
        }

        lines.append("")
        lines.append("Flagged (\(flagRows.count))")
        if flagRows.isEmpty { lines.append("None.") }
        for row in flagRows {
            lines.append("- \(row.flag.surface) · now: \(row.outcome.summary)")
            lines.append("  when flagged: \(row.flag.shownAs)")
            if let sentence = row.flag.sentence, !sentence.isEmpty { lines.append("  sentence: \(sentence)") }
            if let source = row.flag.source, !source.isEmpty { lines.append("  source: \(source)") }
        }

        if !flagRows.isEmpty {
            lines.append("")
            lines.append("Supplement rows (expression, reading, glossary, tags, info, score)")
            var seen = Set<String>()
            for row in flagRows where seen.insert(row.flag.surface).inserted {
                let reading = JapaneseTokenizer.hiraganaReading(for: row.flag.surface)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let info = row.flag.sentence.map { "flagged in: \($0)" } ?? ""
                lines.append([row.flag.surface, reading, "", "", info, ""].joined(separator: "\t"))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cells

    private static func statusIcon(_ status: DictionaryCalloutOutcome.Status, passes: Bool?) -> UIImageView {
        let symbol: String
        let color: UIColor
        switch (status, passes) {
        case (_, .some(true)):
            symbol = "checkmark.circle.fill"; color = .systemGreen
        case (_, .some(false)):
            symbol = "xmark.circle.fill"; color = .systemRed
        case (.defined, nil):
            symbol = "book.closed.fill"; color = .systemGreen
        case (.ambiguous, nil):
            symbol = "questionmark.circle.fill"; color = .systemOrange
        case (.missing, nil):
            symbol = "exclamationmark.circle.fill"; color = .systemRed
        }
        let image = UIImage(systemName: symbol)?.withTintColor(color, renderingMode: .alwaysOriginal)
        return UIImageView(image: image)
    }
}

extension DictionaryChecksViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        blocks.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch blocks[section] {
        case .flags(let rows): return rows.count
        case .fixtures(_, let rows): return rows.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch blocks[section] {
        case .flags(let rows):
            return "Flagged · \(rows.count)"
        case .fixtures(let title, let rows):
            let failed = rows.filter { !$0.passes }.count
            return failed == 0 ? "\(title) · \(rows.count)" : "\(title) · \(rows.count - failed)/\(rows.count)"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        switch blocks[indexPath.section] {
        case .flags(let rows):
            let row = rows[indexPath.row]
            content.text = row.flag.surface
            var lines = ["now: \(row.outcome.summary)"]
            if row.flag.shownAs != row.outcome.summary {
                lines.append("when flagged: \(row.flag.shownAs)")
            }
            if let sentence = row.flag.sentence, !sentence.isEmpty { lines.append(sentence) }
            var meta = [Self.dateFormatter.string(from: row.flag.flaggedAt)]
            if let source = row.flag.source, !source.isEmpty { meta.insert(source, at: 0) }
            lines.append(meta.joined(separator: " · "))
            content.secondaryText = lines.joined(separator: "\n")
            cell.accessoryView = Self.statusIcon(row.outcome.status, passes: nil)

        case .fixtures(_, let rows):
            let row = rows[indexPath.row]
            content.text = "\(row.fixture.surface)  →  \(row.outcome.headword ?? "—")"
            var lines = [row.outcome.summary]
            if let note = row.outcome.note, row.outcome.status == .defined { lines.append(note) }
            if !row.passes {
                lines.append("expected \(row.fixture.expectedHeadword ?? "a definition")")
            }
            if !row.fixture.note.isEmpty { lines.append(row.fixture.note) }
            content.secondaryText = lines.joined(separator: "\n")
            cell.accessoryView = Self.statusIcon(row.outcome.status, passes: row.passes)
        }

        cell.contentConfiguration = content
        cell.backgroundColor = ExperimentPalette.cardSurface
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let surface: String
        switch blocks[indexPath.section] {
        case .flags(let rows): surface = rows[indexPath.row].flag.surface
        case .fixtures(_, let rows): surface = rows[indexPath.row].fixture.surface
        }
        WordDictionaryDetailSheetPresenter.push(surface: surface, from: self)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard case .flags(let rows) = blocks[indexPath.section] else { return nil }
        let id = rows[indexPath.row].flag.id
        let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            DictionaryFlagStore.shared.remove(id: id)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}
