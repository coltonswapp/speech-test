//
//  ClipIssueReportViewController.swift
//  shizen
//
//  "Report an issue" for a clip, as an inset-grouped table. From Clip Details it
//  covers the whole clip; from a line's breakdown screen it carries that line
//  (its own section at the top), and for a split or reading problem the learner
//  can pick the word.
//  Pushed onto a sheet's nav stack, or shown as its own sheet via `makeSheet`.
//

import UIKit

final class ClipIssueReportViewController: UITableViewController, UITextViewDelegate {
    private enum Section {
        case line
        case reason
        case word
        case note
    }

    private let clipID: String
    private let line: ClipLineSnapshot?
    /// The line's words, minus blank tokens.
    private let words: [ClipLineSnapshot.Token]

    private var reason: ClipFeedbackReason?
    private var tokenPosition: Int?
    private var isSending = false

    private let noteCell = ClipIssueNoteCell()
    private lazy var sendItem = UIBarButtonItem(
        title: "Send",
        primaryAction: UIAction { [weak self] _ in self?.send() }
    )

    init(clipID: String, line: ClipLineSnapshot?) {
        self.clipID = clipID
        self.line = line
        words = line?.tokens.filter { !$0.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        super.init(style: .insetGrouped)
        title = "Report an Issue"
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Its own sheet (e.g. over the line breakdown screen).
    static func makeSheet(clipID: String, line: ClipLineSnapshot?) -> UINavigationController {
        let report = ClipIssueReportViewController(clipID: clipID, line: line)
        report.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak report] _ in report?.dismiss(animated: true) }
        )
        let nav = UINavigationController(rootViewController: report)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sendItem.style = .prominent
        sendItem.isEnabled = false
        navigationItem.rightBarButtonItem = sendItem

        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        noteCell.textView.delegate = self
    }

    // MARK: - Sections

    private var sections: [Section] {
        var result: [Section] = []
        if line != nil { result.append(.line) }
        result.append(.reason)
        if showsWords { result.append(.word) }
        result.append(.note)
        return result
    }

    /// The word list only matters for word-level problems on a line.
    private var showsWords: Bool {
        reason?.isAboutAWord == true && !words.isEmpty
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .line, .note: return 1
        case .reason: return ClipFeedbackReason.allCases.count
        case .word: return words.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .line: return "Line"
        case .reason: return "What’s wrong?"
        case .word: return "Which word?"
        case .note: return "Anything else?"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sections[section] {
        case .word: return "Optional. Tap the word that’s wrong."
        case .note: return "Optional."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        if section == .note { return noteCell }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .secondaryLabel
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.accessibilityTraits = .button

        switch section {
        case .line:
            content.text = line?.textJP
            content.textProperties.font = .preferredFont(forTextStyle: .title3)
            let english = line?.textEN?.trimmingCharacters(in: .whitespacesAndNewlines)
            content.secondaryText = english?.isEmpty == false ? english : nil
            content.textToSecondaryTextVerticalPadding = 4
            cell.selectionStyle = .none
            cell.accessibilityTraits = .staticText
        case .reason:
            let option = ClipFeedbackReason.allCases[indexPath.row]
            content.text = option.title
            let selected = option == reason
            cell.accessoryType = selected ? .checkmark : .none
            if selected { cell.accessibilityTraits.insert(.selected) }
        case .word:
            let token = words[indexPath.row]
            content.text = token.surface
            content.secondaryText = token.reading.flatMap { $0 == token.surface ? nil : $0 }
            let selected = token.position == tokenPosition
            cell.accessoryType = selected ? .checkmark : .none
            if selected { cell.accessibilityTraits.insert(.selected) }
        case .note:
            break
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch sections[indexPath.section] {
        case .reason, .word: return indexPath
        case .line, .note: return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .reason:
            selectReason(ClipFeedbackReason.allCases[indexPath.row])
        case .word:
            // Tapping the selected word clears it.
            let position = words[indexPath.row].position
            tokenPosition = tokenPosition == position ? nil : position
            reloadRows(in: .word)
        case .line, .note:
            break
        }
    }

    // MARK: - State

    private func selectReason(_ option: ClipFeedbackReason) {
        let hadWords = showsWords
        reason = option
        if !(reason?.isAboutAWord ?? false) { tokenPosition = nil }

        tableView.performBatchUpdates {
            reloadRows(in: .reason)
            if hadWords != showsWords, let index = sections.firstIndex(of: .reason) {
                let wordSection = IndexSet(integer: index + 1)
                if showsWords {
                    tableView.insertSections(wordSection, with: .fade)
                } else {
                    tableView.deleteSections(wordSection, with: .fade)
                }
            }
        }
        sendItem.isEnabled = !isSending
    }

    /// Refreshes checkmarks in place (no row animation).
    private func reloadRows(in section: Section) {
        guard let index = sections.firstIndex(of: section) else { return }
        for row in 0..<tableView.numberOfRows(inSection: index) {
            let indexPath = IndexPath(row: row, section: index)
            guard let cell = tableView.cellForRow(at: indexPath) else { continue }
            let selected: Bool
            switch section {
            case .reason: selected = ClipFeedbackReason.allCases[row] == reason
            case .word: selected = words[row].position == tokenPosition
            case .line, .note: continue
            }
            cell.accessoryType = selected ? .checkmark : .none
            cell.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    // MARK: - Note

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > 1_000 {
            textView.text = String(textView.text.prefix(1_000))
        }
        noteCell.updatePlaceholder()
        // Let the cell grow with the text.
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
    }

    // MARK: - Send

    private func send() {
        guard let reason, !isSending else { return }
        isSending = true
        sendItem.isEnabled = false
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        view.endEditing(true)

        let note = noteCell.textView.text
        Task { [weak self, clipID, line, tokenPosition] in
            do {
                try await ClipFeedbackClient.reportIssue(
                    clipID: clipID,
                    reason: reason,
                    note: note,
                    line: line,
                    tokenPosition: tokenPosition
                )
                self?.finish()
            } catch {
                self?.failed(error)
            }
        }
    }

    private func finish() {
        let host = presentingViewController
        if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
            nav.topViewController?.showToast(text: "Thanks — we'll take a look")
        } else {
            dismiss(animated: true) {
                host?.showToast(text: "Thanks — we'll take a look")
            }
        }
    }

    private func failed(_ error: Error) {
        isSending = false
        navigationItem.rightBarButtonItem = sendItem
        sendItem.isEnabled = reason != nil
        let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't send. Try again in a moment."
        let alert = UIAlertController(title: "Not Sent", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// A growing text view in a table cell, with a placeholder.
private final class ClipIssueNoteCell: UITableViewCell {
    let textView = UITextView()
    private let placeholder = UILabel()

    init() {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = "Note"
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)

        placeholder.text = "e.g. “It should say ‘tomorrow’, not ‘today’.”"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        placeholder.numberOfLines = 0
        placeholder.isAccessibilityElement = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholder)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: margins.topAnchor),
            textView.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            placeholder.topAnchor.constraint(equalTo: margins.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePlaceholder() {
        placeholder.isHidden = !textView.text.isEmpty
    }
}
