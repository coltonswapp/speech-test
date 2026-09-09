//
//  KanjiDecompositionFinalDefinitionPickerViewController.swift
//  shizen
//
//  Sheet picker for choosing a single final gloss for the
//  KanjiDecompositionCombinedCardView, with a "write in" option.
//

import UIKit

final class KanjiDecompositionFinalDefinitionPickerViewController: UITableViewController {
    private enum Row {
        case definition(index: Int)
        case writeIn
    }

    var onSave: ((String?) -> Void)?

    private let definitions: [String]
    private let selectedDefinition: String

    init(definitions: [String], selectedDefinition: String) {
        self.definitions = definitions
        self.selectedDefinition = selectedDefinition
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Final definition"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.allowsMultipleSelection = false
    }

    private var writeInSelected: Bool {
        !definitions.contains(selectedDefinition)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        definitions.count + 1 // + write-in row
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        let row: Row
        if indexPath.row < definitions.count {
            row = .definition(index: indexPath.row)
        } else {
            row = .writeIn
        }

        let isSelected: Bool
        let title: String
        switch row {
        case .definition(let idx):
            title = definitions[idx]
            isSelected = definitions[idx] == selectedDefinition
        case .writeIn:
            title = "Write in…"
            isSelected = writeInSelected
        }

        var config = UIListContentConfiguration.cell()
        config.text = title
        cell.contentConfiguration = config
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        if indexPath.row < definitions.count {
            let selected = definitions[indexPath.row]
            onSave?(selected)
            dismiss(animated: true)
            return
        }

        presentWriteInPrompt()
    }

    private func presentWriteInPrompt() {
        let current = selectedDefinition
        let alert = UIAlertController(title: "Write in a definition", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let trimmed = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            onSave?(trimmed.isEmpty ? nil : trimmed)
            // Dismiss the prompt, then dismiss the sheet.
            self.dismiss(animated: true) {
                self.dismiss(animated: true)
            }
        })
        present(alert, animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

