//
//  TutorConversationsViewController.swift
//  shizen
//
//  Lists saved realtime tutor transcripts.
//

import UIKit

final class TutorConversationsViewController: UITableViewController {

    private var entries: [TutorConversationEntry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tutor conversations"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadEntries()
    }

    private func reloadEntries() {
        entries = (try? TutorConversationStore.shared.listEntries()) ?? []
        tableView.reloadData()
        if entries.isEmpty {
            tableView.backgroundView = makeEmptyLabel()
        } else {
            tableView.backgroundView = nil
        }
    }

    private func makeEmptyLabel() -> UILabel {
        let label = UILabel()
        label.text = "No saved conversations yet.\n\nTap Save during a tutor session to keep a transcript."
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        return label
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        config.text = entry.preview
        config.secondaryText = String(
            format: "%@ · %d lines%@",
            Self.dateFormatter.string(from: entry.createdAt),
            entry.lineCount,
            entry.hasAudio ? " · audio" : ""
        )
        config.textProperties.numberOfLines = 2
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        do {
            let manifest = try TutorConversationStore.shared.load(at: entry.directoryURL)
            let detail = TutorConversationDetailViewController(
                manifest: manifest,
                directoryURL: entry.directoryURL
            )
            navigationController?.pushViewController(detail, animated: true)
        } catch {
            let alert = UIAlertController(
                title: "Couldn’t open conversation",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else {
                done(false)
                return
            }
            let url = self.entries[indexPath.row].directoryURL
            do {
                try TutorConversationStore.shared.deleteEntry(at: url)
                self.reloadEntries()
                done(true)
            } catch {
                done(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
