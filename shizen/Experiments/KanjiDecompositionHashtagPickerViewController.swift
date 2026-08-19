//
//  KanjiDecompositionHashtagPickerViewController.swift
//  shizen
//
//  Sheet of recommended hashtags for kanji decomposition exports.
//  Select up to five, then copy them to the clipboard in tap order.
//

import UIKit

final class KanjiDecompositionHashtagPickerViewController: UITableViewController {

    private static let maxSelections = 5

    private static let recommendedHashtags = [
        "#learnjapanese",
        "#japanese",
        "#studytok",
        "#jlpt",
        "#kanji",
        "#nihongo",
        "#japaneselanguage",
        "#studyjapanese",
        "#日本語",
        "#languagelearning",
    ]

    /// Hashtags in the order the user tapped them.
    private var selectedInOrder: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hashtags"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Copy",
            style: .done,
            target: self,
            action: #selector(copyTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        updateCopyEnabled()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Self.recommendedHashtags.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Recommended"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Choose up to \(Self.maxSelections). Copy pastes them in the order you selected."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let tag = Self.recommendedHashtags[indexPath.row]
        var config = UIListContentConfiguration.cell()
        config.text = tag
        cell.contentConfiguration = config
        cell.accessoryType = selectedInOrder.contains(tag) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tag = Self.recommendedHashtags[indexPath.row]
        if let index = selectedInOrder.firstIndex(of: tag) {
            selectedInOrder.remove(at: index)
        } else {
            guard selectedInOrder.count < Self.maxSelections else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selectedInOrder.append(tag)
        }
        tableView.reloadData()
        updateCopyEnabled()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func copyTapped() {
        guard !selectedInOrder.isEmpty else { return }
        UIPasteboard.general.string = selectedInOrder.joined(separator: " ")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true)
    }

    private func updateCopyEnabled() {
        navigationItem.rightBarButtonItem?.isEnabled = !selectedInOrder.isEmpty
    }
}
