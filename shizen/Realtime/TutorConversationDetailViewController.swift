//
//  TutorConversationDetailViewController.swift
//  shizen
//
//  Read-only saved tutor transcript.
//

import UIKit

final class TutorConversationDetailViewController: UIViewController {

    private let manifest: TutorConversationManifest
    private let directoryURL: URL
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var lineRows: [UIStackView] = []

    init(manifest: TutorConversationManifest, directoryURL: URL) {
        self.manifest = manifest
        self.directoryURL = directoryURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = Self.dateFormatter.string(from: manifest.createdAt)
        navigationItem.largeTitleDisplayMode = .never

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = JapaneseFuriganaBuilder.transcriptLineSpacing
        contentStack.clipsToBounds = false
        scrollView.addSubview(contentStack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let inset: CGFloat = 24

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12 + JapaneseFuriganaBuilder.transcriptRubyTopInset(for: Self.lyricFont)),
            contentStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            contentStack.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -inset),
        ])

        populateLines()
    }

    private func populateLines() {
        var previousSpeaker: TutorConversationLine.Speaker?
        for line in manifest.lines {
            if let previousSpeaker, previousSpeaker != line.speaker {
                contentStack.setCustomSpacing(JapaneseFuriganaBuilder.transcriptSpeakerTurnSpacing, after: contentStack.arrangedSubviews.last!)
            }
            contentStack.addArrangedSubview(makeLineRow(for: line))
            previousSpeaker = line.speaker
        }
    }

    @objc private func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view as? UIStackView,
              let index = lineRows.firstIndex(where: { $0 === row }),
              manifest.lines.indices.contains(index)
        else { return }
        let line = manifest.lines[index]
        let clip = TutorConversationStore.shared.audioClip(for: line, in: directoryURL)
        let contextLines = manifest.lines.map { entry -> DialogueNuanceContext.Line in
            let speaker: String
            switch entry.speaker {
            case .user: speaker = "You"
            case .assistant: speaker = "Tutor"
            }
            return DialogueNuanceContext.Line(speaker: speaker, japanese: entry.text, english: nil)
        }
        let scrub = SentenceScrubExperimentViewController(
            sentence: line.text,
            recordedClip: clip,
            dialogueContext: DialogueNuanceContext.around(lines: contextLines, focusedIndex: index)
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    private func makeLineRow(for line: TutorConversationLine) -> UIStackView {
        let label = JapaneseFuriganaBuilder.makeTranscriptLabel(font: Self.lyricFont)
        label.textAlignment = line.speaker == .user ? .right : .left
        JapaneseFuriganaBuilder.apply(
            to: label,
            text: line.text,
            font: Self.lyricFont,
            textColor: line.speaker == .user ? .systemBlue : .label
        )

        let textColumn = UIStackView(arrangedSubviews: [label])
        textColumn.axis = .vertical
        textColumn.alignment = line.speaker == .user ? .trailing : .leading
        textColumn.clipsToBounds = false

        let marginSpacer = UIView()
        marginSpacer.translatesAutoresizingMaskIntoConstraints = false
        marginSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        marginSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.clipsToBounds = false
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
        )

        if line.speaker == .user {
            row.addArrangedSubview(marginSpacer)
            row.addArrangedSubview(textColumn)
        } else {
            row.addArrangedSubview(textColumn)
            row.addArrangedSubview(marginSpacer)
        }

        NSLayoutConstraint.activate([
            marginSpacer.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.25),
        ])

        lineRows.append(row)
        return row
    }

    private static let lyricFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 32, weight: .heavy)
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base)
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
