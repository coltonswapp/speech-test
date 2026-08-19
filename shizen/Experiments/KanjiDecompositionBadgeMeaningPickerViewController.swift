//
//  KanjiDecompositionBadgeMeaningPickerViewController.swift
//  shizen
//
//  Sheet for choosing which one-word Kanjidic meanings appear on a
//  kanji decomposition meaning badge (up to two).
//

import UIKit

final class KanjiDecompositionBadgeMeaningPickerViewController: UITableViewController {

    var onSave: (([String]?) -> Void)?

    private let kanji: String
    private let meanings: [String]
    private var selected: [String]

    init(kanji: String, meanings: [String], selectedMeanings: [String]?) {
        self.kanji = kanji
        self.meanings = meanings
        let defaults = Array(meanings.prefix(KanjiDecompositionBadgeMeaningStore.maxSelections))
        if let selectedMeanings, !selectedMeanings.isEmpty {
            let valid = selectedMeanings.filter { meanings.contains($0) }
            self.selected = valid.isEmpty ? defaults : valid
        } else {
            self.selected = defaults
        }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Badge meaning"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.allowsMultipleSelection = false
        updateDoneEnabled()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        meanings.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Meanings for \(kanji)"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Choose up to \(KanjiDecompositionBadgeMeaningStore.maxSelections) one-word definitions to show on the badge. Deselect ones that don’t apply."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let meaning = meanings[indexPath.row]
        var config = UIListContentConfiguration.cell()
        config.text = meaning
        cell.contentConfiguration = config
        cell.accessoryType = selected.contains(meaning) ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let meaning = meanings[indexPath.row]
        if let index = selected.firstIndex(of: meaning) {
            guard selected.count > 1 else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selected.remove(at: index)
        } else {
            guard selected.count < KanjiDecompositionBadgeMeaningStore.maxSelections else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selected.append(meaning)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateDoneEnabled()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        let defaultSelection = Array(meanings.prefix(KanjiDecompositionBadgeMeaningStore.maxSelections))
        // Matching the default list clears any stored preference.
        let result: [String]? = selected == defaultSelection ? nil : selected
        onSave?(result)
        dismiss(animated: true)
    }

    private func updateDoneEnabled() {
        navigationItem.rightBarButtonItem?.isEnabled = !selected.isEmpty
    }
}
