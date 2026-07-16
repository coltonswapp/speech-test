//
//  ExperimentFeedbackSoundDebugViewController.swift
//  shizen
//
//  DEBUG: preview feedback sounds and review exercise assignments.
//

import UIKit

final class ExperimentFeedbackSoundDebugViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case chimes
        case exercises
        case spellingMap
        case uiSounds
        case incorrect

        var title: String {
            switch self {
            case .chimes: return "Success chimes"
            case .exercises: return "Exercise assignments"
            case .spellingMap: return "Spelling (tiles → chime)"
            case .uiSounds: return "UI sounds"
            case .incorrect: return "Incorrect"
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feedback sounds"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section.allCases[section] {
        case .chimes: return ExperimentSuccessChime.allCases.count
        case .exercises: return ExperimentFeedbackExercise.allCases.count
        case .spellingMap: return ExperimentFeedbackSoundCatalog.spellingSyllablePreviewCounts.count
        case .uiSounds: return 1
        case .incorrect: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section.allCases[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()

        switch Section.allCases[indexPath.section] {
        case .chimes:
            let chime = ExperimentSuccessChime.allCases[indexPath.row]
            config.text = chime.assetName
            config.secondaryText = "\(chime.noteCount) notes"
        case .exercises:
            let exercise = ExperimentFeedbackExercise.allCases[indexPath.row]
            config.text = exercise.title
            config.secondaryText = ExperimentFeedbackSoundCatalog.assignmentDescription(for: exercise)
        case .spellingMap:
            let count = ExperimentFeedbackSoundCatalog.spellingSyllablePreviewCounts[indexPath.row]
            let chime = ExperimentFeedbackSoundCatalog.spellingChime(syllableCount: count)
            config.text = "\(count) tile\(count == 1 ? "" : "s")"
            config.secondaryText = chime.displayName
        case .uiSounds:
            config.text = ExperimentFeedbackSoundCatalog.clickAsset
            config.secondaryText =
                "Selection click · tap tests tap path, drag uses engine · volume \(ExperimentFeedbackSoundCatalog.clickVolume)"
        case .incorrect:
            config.text = ExperimentFeedbackSoundCatalog.incorrectAsset
            config.secondaryText = "Wrong answer"
        }

        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        switch Section.allCases[indexPath.section] {
        case .chimes:
            let chime = ExperimentSuccessChime.allCases[indexPath.row]
            ExperimentFeedbackSound.playPreview(assetNamed: chime.assetName)
        case .exercises:
            let exercise = ExperimentFeedbackExercise.allCases[indexPath.row]
            if exercise == .kanaSpelling {
                return
            }
            ExperimentFeedbackSound.playSuccess(for: exercise)
        case .spellingMap:
            let count = ExperimentFeedbackSoundCatalog.spellingSyllablePreviewCounts[indexPath.row]
            ExperimentFeedbackSound.playSuccess(for: .kanaSpelling, spellingSyllableCount: count)
        case .uiSounds:
            ExperimentFeedbackSound.playClick()
            ExperimentFeedbackSound.playDragHoverClick()
        case .incorrect:
            ExperimentFeedbackSound.playIncorrect()
        }
    }
}
