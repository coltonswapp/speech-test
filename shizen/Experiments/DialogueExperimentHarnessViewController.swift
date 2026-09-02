//
//  DialogueExperimentHarnessViewController.swift
//  shizen
//
//  DEBUG: embed DialogueExperimentViewController and switch scenario clips via UIMenu.
//

import AVFoundation
import TTSCore
import UIKit

enum DialogueExperimentCatalog {

    struct Entry: Hashable {
        let id: String
        let pointID: String
        let pointTitle: String
        let example: GrammarExample
        let menuTitle: String
        let menuSubtitle: String
        let hasBundledAudio: Bool
    }

    static var entries: [Entry] {
        GrammarCurriculum.n5Points.flatMap { point in
            point.examples.enumerated().compactMap { index, example in
                guard let scenario = example.scenario, !scenario.lines.isEmpty else { return nil }

                let audioKey = example.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let clipName: String
                if audioKey.isEmpty {
                    clipName = "example-\(index)"
                } else {
                    clipName = audioKey.split(separator: "/").last.map(String.init) ?? audioKey
                }

                let hasAudio = !audioKey.isEmpty && GrammarAudioCatalog.bundledURL(for: audioKey) != nil
                let lineCount = scenario.lines.count + (example.japanese.isEmpty ? 0 : 1)
                let audioLabel = hasAudio ? "bundled audio" : (audioKey.isEmpty ? "no audioKey" : "missing clip")
                let subtitle = "\(lineCount) lines · \(audioLabel)"

                return Entry(
                    id: audioKey.isEmpty ? "\(point.id)/example-\(index)" : audioKey,
                    pointID: point.id,
                    pointTitle: point.title,
                    example: example,
                    menuTitle: clipName,
                    menuSubtitle: subtitle,
                    hasBundledAudio: hasAudio
                )
            }
        }
    }

    static func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    static func makeScenarioMenu(
        selectedEntryID: String,
        onSelect: @escaping (Entry) -> Void
    ) -> UIMenu {
        let grouped = Dictionary(grouping: entries, by: \.pointID)
        let pointOrder = GrammarCurriculum.n5Points.map(\.id)

        let submenus: [UIMenuElement] = pointOrder.compactMap { pointID in
            guard let pointEntries = grouped[pointID], !pointEntries.isEmpty else { return nil }
            let pointTitle = pointEntries[0].pointTitle
            let actions = pointEntries.map { entry in
                UIAction(
                    title: entry.menuTitle,
                    subtitle: entry.menuSubtitle,
                    state: entry.id == selectedEntryID ? .on : .off
                ) { _ in
                    onSelect(entry)
                }
            }
            return UIMenu(title: pointTitle, options: .displayInline, children: actions)
        }

        return UIMenu(
            title: "Scenario clips",
            options: .singleSelection,
            children: submenus
        )
    }
}

// MARK: - Alignment diagnostics (console)

private enum DialogueHarnessAlignmentLogger {

    static func log(_ message: String) {
        print("[DialogueHarness] \(message)")
    }

    private static func fmt(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }

    static func logLoad(_ entry: DialogueExperimentCatalog.Entry) {
        log("——— loaded clip: \(entry.menuTitle) (\(entry.id)) ———")
        let spokenLines = GrammarExampleDialogueLines.lines(for: entry.example)
        log("spoken lines (\(spokenLines.count)):")
        for (index, text) in spokenLines.enumerated() {
            log("  [\(index)] \(text)")
        }
    }

    static func logAlignmentDiagnostics(for entry: DialogueExperimentCatalog.Entry) {
        DispatchQueue.global(qos: .userInitiated).async {
            logAlignmentDiagnosticsOffMain(for: entry)
        }
    }

    private static func logAlignmentDiagnosticsOffMain(for entry: DialogueExperimentCatalog.Entry) {
        guard let audioKey = entry.example.audioKey,
              let url = GrammarAudioCatalog.bundledURL(for: audioKey) else {
            log("WARNING: no bundled audio URL for \(entry.menuTitle)")
            return
        }

        let spokenLines = GrammarExampleDialogueLines.lines(for: entry.example)
        let playerDuration: TimeInterval = {
            guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return 0 }
            return player.duration
        }()
        let pcm = try? TTSAudioFileLoader.loadMonoFloatSamples(from: url)
        let sampleRate = pcm?.sampleRate ?? 24_000
        let samples = pcm?.samples ?? []

        log("audio file: \(url.lastPathComponent) · duration \(String(format: "%.3f", playerDuration))s")
        if let embedded = DialogueAlignmentMetadata.readLineSwitchSeconds(from: url) {
            log("embedded M4A line switches: \(embedded.map { fmt($0) }.joined(separator: ", "))")
            if embedded.count == max(0, spokenLines.count - 1) {
                log("embedded metadata matches line count → using embedded switches (skipping VAD)")
            } else if !embedded.isEmpty {
                log("WARNING: embedded switch count (\(embedded.count)) ≠ expected (\(max(0, spokenLines.count - 1))) — falling back to VAD")
            }
        } else {
            log("embedded M4A line switches: none (using VAD/heuristics)")
        }
        log("PCM decode: \(samples.isEmpty ? "FAILED" : "\(samples.count) samples @ \(Int(sampleRate)) Hz")")

        if !samples.isEmpty {
            let vad = TTSAudioAlignment.vadSpeechRegions(samples: samples, sampleRate: sampleRate)
            log("VAD speech regions: \(vad.count) (spoken lines: \(spokenLines.count))")
            for (index, region) in vad.enumerated() {
                let start = Double(region.lowerBound) / sampleRate
                let end = Double(region.upperBound) / sampleRate
                log("  VAD[\(index)] \(fmt(start))–\(fmt(end)) (\(fmt(end - start))s)")
            }
            if vad.count == spokenLines.count {
                log("VAD count matches line count → using speech-onset boundaries")
            } else if vad.count != spokenLines.count {
                let onsets = speechOnsetCandidatesForLogging(samples: samples, sampleRate: sampleRate, vad: vad)
                log("VAD/line mismatch → \(onsets.count) speech-onset candidates: \(onsets.map { fmt($0) }.joined(separator: ", "))")
            }

            let strictMarkers = TTSAudioAlignment.detectedMarkerSilenceRuns(
                samples: samples,
                sampleRate: sampleRate
            )
            let softValleys = TTSAudioAlignment.detectedSoftMarkerValleys(
                samples: samples,
                sampleRate: sampleRate
            )
            let needed = max(0, spokenLines.count - 1)
            log("strict 0.15s markers: \(strictMarkers.count) (need \(needed))")
            for (index, run) in strictMarkers.enumerated() {
                let start = Double(run.lowerBound) / sampleRate
                let end = Double(run.upperBound) / sampleRate
                log("  marker[\(index)] \(fmt(start))–\(fmt(end)) (\(fmt(end - start))s)")
            }
            if !softValleys.isEmpty {
                log("soft RMS valleys (diagnostic only): \(softValleys.count)")
                for (index, run) in softValleys.enumerated() {
                    let start = Double(run.lowerBound) / sampleRate
                    let end = Double(run.upperBound) / sampleRate
                    log("  valley[\(index)] \(fmt(start))–\(fmt(end)) (\(fmt(end - start))s)")
                }
            }
            if vad.count >= 2, vad.count < spokenLines.count {
                log("VAD gap split → inter-region cut + tail sub-onsets (lines \(vad.count) regions / \(spokenLines.count) lines)")
            } else if strictMarkers.count >= needed {
                log("strict markers available → using marker boundaries")
            }
        }

        let aligned = TTSAudioAlignment.segmentTimeRanges(
            lineTexts: spokenLines,
            duration: playerDuration,
            samples: pcm?.samples,
            sampleRate: sampleRate,
            audioURL: url
        )
        log("final aligned switch points:")
        if aligned.isEmpty {
            log("  WARNING: alignment produced no ranges")
        } else {
            for (index, line) in aligned.enumerated() {
                let lo = String(format: "%.3f", line.timeRange.lowerBound)
                let hi = String(format: "%.3f", line.timeRange.upperBound)
                log("  [\(index)] switch≥\(lo)s · active until <\(hi)s · \"\(line.text)\"")
            }
            if aligned.count >= 2 {
                for index in 1..<aligned.count {
                    let gap = aligned[index].timeRange.lowerBound - aligned[index - 1].timeRange.lowerBound
                    log("  gap line \(index - 1)→\(index): \(fmt(gap))s between switch points")
                }
            }
        }
        log("——— end \(entry.menuTitle) ———")
    }

    private static func speechOnsetCandidatesForLogging(
        samples: [Float],
        sampleRate: Double,
        vad: [Range<Int>]
    ) -> [Double] {
        guard !vad.isEmpty else { return [] }
        var candidates: [Int] = []
        for index in 1..<vad.count {
            candidates.append(vad[index].lowerBound)
        }
        for region in vad.dropFirst() {
            let slice = Array(samples[region.lowerBound..<region.upperBound])
            guard !slice.isEmpty else { continue }
            let subsegments = TTSAudioAlignment.vadSpeechRegions(
                samples: slice,
                sampleRate: sampleRate,
                minSilenceSeconds: 0.080,
                minSpeechSeconds: 0.040
            )
            for sub in subsegments {
                candidates.append(region.lowerBound + sub.lowerBound)
            }
        }
        return Array(Set(candidates)).sorted().map { Double($0) / sampleRate }
    }
}

final class DialogueExperimentHarnessViewController: UIViewController {

    private let containerView = UIView()
    private var dialogueViewController: DialogueExperimentViewController?
    private var selectedEntryID: String

    init(initialEntryID: String? = nil) {
        let entries = DialogueExperimentCatalog.entries
        let defaultEntryID = DialogueExperimentFixture.audioKey
        selectedEntryID = initialEntryID.flatMap { id in
            entries.contains(where: { $0.id == id }) ? id : nil
        } ?? (entries.contains(where: { $0.id == defaultEntryID }) ? defaultEntryID : entries.first?.id ?? "")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        let entries = DialogueExperimentCatalog.entries
        let defaultEntryID = DialogueExperimentFixture.audioKey
        selectedEntryID = entries.contains(where: { $0.id == defaultEntryID })
            ? defaultEntryID
            : entries.first?.id ?? ""
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureNavigationItems()

        if let entry = currentEntry {
            embedDialogue(for: entry)
        }
    }

    private var currentEntry: DialogueExperimentCatalog.Entry? {
        DialogueExperimentCatalog.entry(id: selectedEntryID)
            ?? DialogueExperimentCatalog.entries.first
    }

    private func configureNavigationItems() {
        navigationItem.title = currentEntry?.menuTitle ?? "Dialogue"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward"),
            primaryAction: nil,
            menu: makeDialogueMenu()
        )
    }

    private func makeDialogueMenu() -> UIMenu {
        DialogueExperimentCatalog.makeScenarioMenu(selectedEntryID: selectedEntryID) { [weak self] entry in
            self?.selectEntry(entry)
        }
    }

    private func selectEntry(_ entry: DialogueExperimentCatalog.Entry) {
        guard entry.id != selectedEntryID else { return }
        selectedEntryID = entry.id
        navigationItem.title = entry.menuTitle
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        embedDialogue(for: entry)
    }

    private func embedDialogue(for entry: DialogueExperimentCatalog.Entry) {
        DialogueHarnessAlignmentLogger.logLoad(entry)
        DialogueHarnessAlignmentLogger.logAlignmentDiagnostics(for: entry)

        if let dialogue = dialogueViewController {
            dialogue.alignmentDebugLog = { DialogueHarnessAlignmentLogger.log($0) }
            dialogue.reloadScenario(pointTitle: entry.pointTitle, example: entry.example)
            return
        }

        let dialogue = DialogueExperimentViewController(
            pointTitle: entry.pointTitle,
            example: entry.example
        )
        dialogue.alignmentDebugLog = { DialogueHarnessAlignmentLogger.log($0) }
        addChild(dialogue)
        dialogue.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dialogue.view)
        NSLayoutConstraint.activate([
            dialogue.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            dialogue.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dialogue.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            dialogue.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        dialogue.didMove(toParent: self)
        dialogueViewController = dialogue
    }
}
