//
//  VerbComboListViewController.swift
//  shizen
//
//  Picker for generated pattern slideshows. Each row opens its own 5-still export.
//

import UIKit

final class VerbComboListViewController: UITableViewController {

    private let decks: [VerbComboDeck]

    init(decks: [VerbComboDeck]) {
        self.decks = decks
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Verb combinations"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "deck")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        decks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "deck", for: indexPath)
        let deck = decks[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = deck.hookVerb
        content.secondaryText = deck.rule
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            VerbComboPagerViewController(deck: decks[indexPath.row]),
            animated: true
        )
    }
}
