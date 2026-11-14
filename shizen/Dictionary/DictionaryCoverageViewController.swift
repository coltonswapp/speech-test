//
//  DictionaryCoverageViewController.swift
//  shizen
//
//  Debug screen: sweeps every lesson for words the token-tap callout can't define,
//  then exports a review CSV and paste-ready rows for `scripts/jmdict_supplement.tsv`.
//

import UIKit

final class DictionaryCoverageViewController: UITableViewController {

    private enum Filter: Int, CaseIterable {
        case hidden
        case weak
        case all

        var title: String {
            switch self {
            case .hidden: return "No callout"
            case .weak: return "Weak"
            case .all: return "All"
            }
        }

        var statuses: Set<DictionaryCoverageReport.Status> {
            switch self {
            case .hidden: return [.missing, .untrustedKana]
            case .weak: return [.weak]
            case .all: return Set(DictionaryCoverageReport.Status.allCases)
            }
        }
    }

    private var report: DictionaryCoverageReport?
    private var visibleItems: [DictionaryCoverageReport.Item] = []
    private var filter: Filter = .hidden
    private var isRunning = false
    private var runTask: Task<Void, Never>?

    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let statusLabel = UILabel()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            runTask?.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dictionary Coverage"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        filterControl.selectedSegmentIndex = filter.rawValue
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = ContentCMSClient.isConfigured
            ? "Scans every published CMS lesson."
            : "CMS not configured. Scans bundled lessons only."

        let header = UIStackView(arrangedSubviews: [filterControl, statusLabel])
        header.axis = .vertical
        header.spacing = 10
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20)
        tableView.tableHeaderView = header
        sizeHeaderToFit()

        updateNavigationItems()
        run()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderToFit()
    }

    // MARK: - Run

    @objc private func run() {
        guard !isRunning else { return }
        isRunning = true
        updateNavigationItems()
        runTask = Task { [weak self] in
            let collections = await DictionaryCoverageSweep.loadCollections { message in
                self?.setStatus(message)
            }
            guard !Task.isCancelled else { return }
            let report = await DictionaryCoverageSweep.run(collections: collections) { message in
                self?.setStatus(message)
            }
            guard let self, !Task.isCancelled else { return }
            self.report = report
            self.isRunning = false
            self.applyFilter()
            self.setStatus(self.summary(for: report))
            self.updateNavigationItems()
        }
    }

    private func summary(for report: DictionaryCoverageReport) -> String {
        let missing = report.items(with: [.missing]).count
        let untrusted = report.items(with: [.untrustedKana]).count
        let weak = report.items(with: [.weak]).count
        return """
        \(report.lessonCount) lessons · \(report.lineCount) lines (\(report.studioTokenLineCount) with Studio tokens) · \
        \(report.uniqueSurfaceCount) unique words
        \(missing) no entry · \(untrusted) kana hit rejected · \(weak) weak match
        """
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
        sizeHeaderToFit()
    }

    private func sizeHeaderToFit() {
        guard let header = tableView.tableHeaderView else { return }
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        guard abs(header.frame.height - size.height) > 0.5 || header.frame.width != width else { return }
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = header
    }

    private func updateNavigationItems() {
        if isRunning {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: spinner)]
            return
        }
        let rerun = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(run)
        )
        let export = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), menu: exportMenu())
        export.isEnabled = report != nil
        navigationItem.rightBarButtonItems = [export, rerun]
    }

    // MARK: - Filter

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .hidden
        applyFilter()
        updateNavigationItems()
    }

    private func applyFilter() {
        visibleItems = report?.items(with: filter.statuses) ?? []
        tableView.reloadData()
    }

    // MARK: - Export

    private func exportMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Share review CSV", image: UIImage(systemName: "tablecells")) { [weak self] _ in
                self?.shareReviewCSV()
            },
            UIAction(
                title: "Copy supplement rows (\(filter.title))",
                image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                self?.copySupplementRows()
            },
        ])
    }

    private func shareReviewCSV() {
        guard let report else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictionary-coverage-\(stamp).csv")
        do {
            try report.reviewCSV().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            setStatus("Couldn't write CSV: \(error.localizedDescription)")
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }

    private func copySupplementRows() {
        guard let report else { return }
        UIPasteboard.general.string = report.supplementTSV(statuses: filter.statuses)
        let count = report.items(with: filter.statuses).count
        let alert = UIAlertController(
            title: "Copied \(count) rows",
            message: "Paste into scripts/jmdict_supplement.tsv, fill in the glossary column, then rebuild jmdict.sqlite.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard report != nil, visibleItems.isEmpty else { return nil }
        return "Nothing flagged."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = visibleItems[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = item.reading.isEmpty || item.reading == item.surface
            ? item.surface
            : "\(item.surface)  \(item.reading)"
        content.textProperties.font = .preferredFont(forTextStyle: .headline)

        var meta = "\(item.status.label) · \(item.hitCount)×"
        if let headword = item.matchedHeadword, headword != item.surface {
            meta += " · → \(headword)"
        }
        if let lesson = item.lessonTitles.first {
            meta += item.lessonTitles.count > 1
                ? " · \(lesson) +\(item.lessonTitles.count - 1)"
                : " · \(lesson)"
        }
        let example = item.occurrences.first?.sentence ?? ""
        content.secondaryText = example.isEmpty ? meta : "\(meta)\n\(example)"
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let item = visibleItems[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIMenuElement] = [
                UIAction(title: "Copy word", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = item.surface
                },
            ]
            if let sentence = item.occurrences.first?.sentence {
                actions.append(UIAction(title: "Copy example sentence", image: UIImage(systemName: "text.quote")) { _ in
                    UIPasteboard.general.string = sentence
                })
            }
            return UIMenu(children: actions)
        }
    }
}
