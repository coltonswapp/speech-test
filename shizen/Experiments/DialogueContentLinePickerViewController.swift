//
//  DialogueContentLinePickerViewController.swift
//  shizen
//
//  Choose which spoken lines to put on camera. Conversation and two-pass
//  replay are a checklist (original order). Response quiz assigns prompt /
//  correct / two distractors.
//

import UIKit

final class DialogueContentLinePickerViewController: UIViewController {

    enum Mode {
        case pushToPlayer
        case editExisting(DialogueContentSession)
    }

    var onSessionReady: ((DialogueContentSession) -> Void)?

    private let collection: DialogueScenarioCollection
    private let scenario: DialogueScenarioCollection.Scenario
    private let format: DialogueContentFormat
    private let mode: Mode

    private var scenarioLines: [DialogueContentSpokenLine] = []
    private var elsewhereLines: [DialogueContentSpokenLine] = []

    private var selectedIDs: Set<String> = []
    private var promptID: String?
    private var correctID: String?
    private var distractorIDs: [String] = []
    private var hookText: String

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DialogueContentSpokenLine>!
    private var continueButton: UIBarButtonItem?

    private nonisolated enum Section: Int, Hashable, Sendable {
        case scenario
        case elsewhere
    }

    init(
        collection: DialogueScenarioCollection,
        scenario: DialogueScenarioCollection.Scenario,
        format: DialogueContentFormat,
        mode: Mode = .pushToPlayer
    ) {
        self.collection = collection
        self.scenario = scenario
        self.format = format
        self.mode = mode
        switch mode {
        case .pushToPlayer:
            self.hookText = format.defaultHookText
        case .editExisting(let session):
            self.hookText = session.hookText
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = format.selectsSpokenLines ? "Lines" : "Assign lines"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        scenarioLines = DialogueContentLineCatalog.spokenLines(in: scenario)
            .filter { !$0.isStageLine }
        elsewhereLines = format.selectsSpokenLines
            ? []
            : DialogueContentLineCatalog.spokenLinesElsewhere(in: collection, excluding: scenario.id)

        applyInitialSelection()
        configureCollectionView()
        configureContinueButton()
        applySnapshot()
        updateContinueEnabled()
    }

    private func applyInitialSelection() {
        switch mode {
        case .pushToPlayer:
            if format.selectsSpokenLines {
                selectedIDs = Set(scenarioLines.map(\.id))
            }
        case .editExisting(let session):
            selectedIDs = Set(session.selectedLines.map(\.id))
            promptID = session.prompt?.id
            correctID = session.correct?.id
            distractorIDs = session.distractors.map(\.id)
        }
    }

    private func configureContinueButton() {
        let title: String
        switch mode {
        case .pushToPlayer: title = "Continue"
        case .editExisting: title = "Done"
        }
        let button = UIBarButtonItem(
            title: title,
            style: .done,
            target: self,
            action: #selector(continueTapped)
        )
        continueButton = button
        navigationItem.rightBarButtonItem = button
    }

    private func configureCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.headerMode = .supplementary
        listConfiguration.footerMode = format.selectsSpokenLines ? .none : .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = format.selectsSpokenLines
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DialogueContentSpokenLine> {
            [weak self] cell, _, line in
            guard let self else { return }
            var content = UIListContentConfiguration.subtitleCell()
            content.text = "\(line.speakerPrefix) \(line.japanese)"
            content.textProperties.numberOfLines = 0
            let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            content.secondaryText = english.isEmpty ? line.scenarioTitle : english
            content.secondaryTextProperties.numberOfLines = 2
            cell.contentConfiguration = content

            if self.format.selectsSpokenLines {
                cell.accessories = self.selectedIDs.contains(line.id) ? [.checkmark()] : []
            } else {
                cell.accessories = self.roleAccessory(for: line)
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            let section = self?.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            switch section {
            case .scenario:
                content.text = self?.scenario.menuTitle ?? "This scenario"
            case .elsewhere:
                content.text = "Elsewhere in this lesson"
            case .none:
                content.text = nil
            }
            header.contentConfiguration = content
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footer, _, indexPath in
            var content = UIListContentConfiguration.groupedFooter()
            let section = self?.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            switch section {
            case .scenario:
                content.text = "Prompt and correct reply must come from this scenario so their audio plays. Tap a row to assign a role."
            case .elsewhere:
                content.text = "Distractors only — these lines appear as text, without audio."
            case .none:
                content.text = nil
            }
            footer.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, DialogueContentSpokenLine>(
            collectionView: collectionView
        ) { collectionView, indexPath, line in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: line
            )
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: headerRegistration,
                    for: indexPath
                )
            }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: footerRegistration,
                for: indexPath
            )
        }
    }

    private func roleAccessory(for line: DialogueContentSpokenLine) -> [UICellAccessory] {
        let label: String?
        if line.id == promptID {
            label = "Prompt"
        } else if line.id == correctID {
            label = "Correct"
        } else if distractorIDs.contains(line.id) {
            let slot = (distractorIDs.firstIndex(of: line.id) ?? 0) + 1
            label = "Wrong \(slot)"
        } else {
            label = nil
        }
        guard let label else { return [] }
        return [.label(text: label)]
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, DialogueContentSpokenLine>()
        snapshot.appendSections([.scenario])
        snapshot.appendItems(scenarioLines, toSection: .scenario)
        if !format.selectsSpokenLines, !elsewhereLines.isEmpty {
            snapshot.appendSections([.elsewhere])
            snapshot.appendItems(elsewhereLines, toSection: .elsewhere)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reloadVisibleRoles() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        updateContinueEnabled()
    }

    private func line(for id: String) -> DialogueContentSpokenLine? {
        scenarioLines.first(where: { $0.id == id })
            ?? elsewhereLines.first(where: { $0.id == id })
    }

    private func updateContinueEnabled() {
        continueButton?.isEnabled = makeSession()?.isReadyToRecord == true
    }

    private func makeSession() -> DialogueContentSession? {
        switch format {
        case .fullConversation, .twoPassReplay:
            let selected = scenarioLines.filter { selectedIDs.contains($0.id) }
            guard !selected.isEmpty else { return nil }
            return DialogueContentSession(
                collection: collection,
                scenario: scenario,
                format: format,
                hookText: hookText,
                selectedLines: selected,
                prompt: nil,
                correct: nil,
                distractors: []
            )
        case .responseQuiz:
            guard let promptID, let correctID,
                  let prompt = scenarioLines.first(where: { $0.id == promptID }),
                  let correct = scenarioLines.first(where: { $0.id == correctID })
            else { return nil }
            let distractors = distractorIDs.compactMap { line(for: $0) }
            guard distractors.count == 2 else { return nil }
            return DialogueContentSession(
                collection: collection,
                scenario: scenario,
                format: .responseQuiz,
                hookText: hookText,
                selectedLines: [],
                prompt: prompt,
                correct: correct,
                distractors: distractors
            )
        }
    }

    @objc private func continueTapped() {
        guard let session = makeSession() else { return }
        switch mode {
        case .pushToPlayer:
            if let onSessionReady {
                onSessionReady(session)
                return
            }
            let player = DialogueContentRecordingViewController(session: session)
            navigationController?.pushViewController(player, animated: true)
        case .editExisting:
            onSessionReady?(session)
            if presentingViewController != nil {
                dismiss(animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        }
    }
}

extension DialogueContentLinePickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let line = dataSource.itemIdentifier(for: indexPath) else { return }
        switch format {
        case .fullConversation, .twoPassReplay:
            if selectedIDs.contains(line.id) {
                selectedIDs.remove(line.id)
            } else {
                selectedIDs.insert(line.id)
            }
            reloadVisibleRoles()
        case .responseQuiz:
            presentRoleMenu(for: line, inScenarioSection: indexPath.section == 0)
        }
    }

    private func presentRoleMenu(for line: DialogueContentSpokenLine, inScenarioSection: Bool) {
        let sheet = UIAlertController(
            title: line.speakerPrefix,
            message: line.japanese,
            preferredStyle: .actionSheet
        )

        if inScenarioSection {
            sheet.addAction(UIAlertAction(title: "Prompt", style: .default) { [weak self] _ in
                self?.assignPrompt(line)
            })
            sheet.addAction(UIAlertAction(title: "Correct reply", style: .default) { [weak self] _ in
                self?.assignCorrect(line)
            })
        }

        let distractorTitle = distractorIDs.contains(line.id)
            ? "Already a distractor"
            : (distractorIDs.count >= 2 ? "Distractor (replace oldest)" : "Distractor")
        sheet.addAction(UIAlertAction(title: distractorTitle, style: .default) { [weak self] _ in
            self?.assignDistractor(line)
        })

        if promptID == line.id || correctID == line.id || distractorIDs.contains(line.id) {
            sheet.addAction(UIAlertAction(title: "Clear role", style: .destructive) { [weak self] _ in
                self?.clearRole(line)
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController,
           let cell = collectionView.cellForItem(
            at: dataSource.indexPath(for: line) ?? IndexPath(item: 0, section: 0)
           ) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func assignPrompt(_ line: DialogueContentSpokenLine) {
        if correctID == line.id { correctID = nil }
        distractorIDs.removeAll { $0 == line.id }
        promptID = line.id
        reloadVisibleRoles()
    }

    private func assignCorrect(_ line: DialogueContentSpokenLine) {
        if promptID == line.id { promptID = nil }
        distractorIDs.removeAll { $0 == line.id }
        correctID = line.id
        reloadVisibleRoles()
    }

    private func assignDistractor(_ line: DialogueContentSpokenLine) {
        if promptID == line.id { promptID = nil }
        if correctID == line.id { correctID = nil }
        distractorIDs.removeAll { $0 == line.id }
        if distractorIDs.count >= 2 {
            distractorIDs.removeFirst()
        }
        distractorIDs.append(line.id)
        reloadVisibleRoles()
    }

    private func clearRole(_ line: DialogueContentSpokenLine) {
        if promptID == line.id { promptID = nil }
        if correctID == line.id { correctID = nil }
        distractorIDs.removeAll { $0 == line.id }
        reloadVisibleRoles()
    }
}
