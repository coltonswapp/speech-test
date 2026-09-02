//
//  DialogueRolePlaySheetViewController.swift
//  shizen
//
//  Native page sheet for Role Play speaker choice and the completion recap.
//  Expanding completion to the large detent reveals STT debug stats.
//

import UIKit

struct RolePlayCompareTurnSnapshot {
    let targetJapanese: String
    let onDeviceText: String
    let whisperText: String
}

final class DialogueRolePlaySheetViewController: UIViewController, UISheetPresentationControllerDelegate {

    enum Mode {
        case pickRole(speakers: [String])
        case complete(
            usageText: String?,
            compareSnapshots: [RolePlayCompareTurnSnapshot]
        )
    }

    var onSelectSpeaker: ((String) -> Void)?
    var onReplay: (() -> Void)?
    var onSwitchRoles: (() -> Void)?
    var onDone: (() -> Void)?
    var onDismissed: (() -> Void)?

    private var mode: Mode
    private var hasCommittedAction = false

    private let scrollView = UIScrollView()
    private let rootStack = UIStackView()
    private let debugStack = UIStackView()
    private let usageLabel = UILabel()
    private let compareStack = UIStackView()
    private let buttonsStack = UIStackView()

    private static let buttonSpacing: CGFloat = 10

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        configureChrome()
        apply(mode, animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingSheet?.delegate = self
        navigationController?.presentationController?.delegate = self
    }

    func apply(_ mode: Mode, animated: Bool = true) {
        self.mode = mode
        hasCommittedAction = false
        rebuildContent()
        configureSheetPresentation()
        updateDebugVisibility(animated: animated)
    }

    func updateUsageText(_ text: String?) {
        guard case .complete(let current, let snapshots) = mode else { return }
        guard current != text else { return }
        let previousHadDebug = hasDebugContent
        mode = .complete(usageText: text, compareSnapshots: snapshots)
        rebuildDebugContent()
        updateDebugVisibility(animated: false)
        if previousHadDebug != hasDebugContent {
            configureSheetPresentation()
        }
    }

    // MARK: - Layout

    private func configureChrome() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true

        debugStack.axis = .vertical
        debugStack.alignment = .fill
        debugStack.spacing = 16
        debugStack.isHidden = true

        usageLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        usageLabel.textAlignment = .left
        usageLabel.numberOfLines = 0
        usageLabel.textColor = .secondaryLabel

        compareStack.axis = .vertical
        compareStack.alignment = .fill
        compareStack.spacing = 10

        buttonsStack.axis = .vertical
        buttonsStack.alignment = .fill
        buttonsStack.spacing = Self.buttonSpacing
        buttonsStack.setContentHuggingPriority(.required, for: .vertical)
        buttonsStack.setContentCompressionResistancePriority(.required, for: .vertical)

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 16
        rootStack.addArrangedSubview(buttonsStack)
        rootStack.addArrangedSubview(debugStack)

        view.addSubview(scrollView)
        scrollView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rootStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            rootStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            rootStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func rebuildContent() {
        switch mode {
        case .pickRole(let speakers):
            title = "Choose your part"
            navigationItem.subtitle = "Speak as 1 of \(speakers.count) people"
            navigationItem.rightBarButtonItem = nil
            navigationController?.isModalInPresentation = true
            rebuildPickerButtons(speakers: speakers)
        case .complete:
            title = "Role play complete"
            navigationItem.subtitle = "Speaking proficiency comes through repetition & imitation."
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .done,
                primaryAction: UIAction { [weak self] _ in
                    self?.handleDone()
                }
            )
            navigationController?.isModalInPresentation = false
            rebuildCompletionButtons()
        }
        rebuildDebugContent()
    }

    private func rebuildPickerButtons(speakers: [String]) {
        clearButtons()
        for speaker in speakers {
            let button = makeChoiceButton(title: speaker)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button, !self.hasCommittedAction else { return }
                self.hasCommittedAction = true
                button.setChosen(true)
                self.onSelectSpeaker?(button.value)
            }, for: .touchUpInside)
            buttonsStack.addArrangedSubview(button)
        }
    }

    private func rebuildCompletionButtons() {
        clearButtons()

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = Self.buttonSpacing
        row.setContentHuggingPriority(.required, for: .vertical)

        let switchRoles = makeChoiceButton(title: "Switch Roles")
        switchRoles.addAction(UIAction { [weak self] _ in
            self?.onSwitchRoles?()
        }, for: .touchUpInside)

        let replay = makeChoiceButton(title: "Replay")
        replay.addAction(UIAction { [weak self] _ in
            guard let self, !self.hasCommittedAction else { return }
            self.hasCommittedAction = true
            self.onReplay?()
        }, for: .touchUpInside)

        row.addArrangedSubview(switchRoles)
        row.addArrangedSubview(replay)
        buttonsStack.addArrangedSubview(row)
    }

    private func makeChoiceButton(title: String) -> KanaChoiceButton {
        KanaChoiceButton(
            value: title,
            labelStyle: .compact,
            preferredHeight: PrimaryButton.preferredHeight
        )
    }

    private func clearButtons() {
        buttonsStack.arrangedSubviews.forEach {
            buttonsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func handleDone() {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        onDone?()
    }

    private func rebuildDebugContent() {
        debugStack.arrangedSubviews.forEach {
            debugStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        compareStack.arrangedSubviews.forEach {
            compareStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard case .complete(let usageText, let snapshots) = mode else { return }

        if let usageText, !usageText.isEmpty {
            usageLabel.text = usageText
            debugStack.addArrangedSubview(usageLabel)
        }

        if !snapshots.isEmpty {
            let heading = UILabel()
            heading.font = .preferredFont(forTextStyle: .caption1)
            heading.textColor = .secondaryLabel
            heading.textAlignment = .center
            heading.text = "On Device vs GPT Whisper"
            compareStack.addArrangedSubview(heading)
            for snapshot in snapshots {
                compareStack.addArrangedSubview(makeCompareRecapCard(snapshot))
            }
            debugStack.addArrangedSubview(compareStack)
        }
    }

    private var hasDebugContent: Bool {
        guard case .complete(let usageText, let snapshots) = mode else { return false }
        let hasUsage = usageText?.isEmpty == false
        return hasUsage || !snapshots.isEmpty
    }

    private var hostingSheet: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }

    private var isExpandedToLarge: Bool {
        hostingSheet?.selectedDetentIdentifier == .large
    }

    private func updateDebugVisibility(animated: Bool) {
        let visible = hasDebugContent && isExpandedToLarge
        let changes = {
            self.debugStack.isHidden = !visible
            self.scrollView.alwaysBounceVertical = visible
        }
        guard animated, view.window != nil else {
            changes()
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            changes()
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Sheet

    private func configureSheetPresentation() {
        guard let sheet = hostingSheet else { return }
        sheet.delegate = self
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true

        switch mode {
        case .pickRole:
            sheet.detents = [.medium()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        case .complete:
            if hasDebugContent {
                sheet.detents = [.medium(), .large()]
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            } else {
                sheet.detents = [.medium()]
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
            if sheet.selectedDetentIdentifier != .large {
                sheet.selectedDetentIdentifier = .medium
            }
        }
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        updateDebugVisibility(animated: true)
        if isExpandedToLarge {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismissed?()
    }

    // MARK: - Compare recap

    private func makeCompareRecapCard(_ snapshot: RolePlayCompareTurnSnapshot) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemFill
        card.layer.cornerRadius = 14
        card.clipsToBounds = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6

        let targetLabel = UILabel()
        targetLabel.font = .preferredFont(forTextStyle: .subheadline)
        targetLabel.textColor = .label
        targetLabel.numberOfLines = 0
        targetLabel.text = snapshot.targetJapanese.trimmingCharacters(in: .whitespacesAndNewlines)

        let onDevicePercent = compareMatchPercent(heard: snapshot.onDeviceText, target: snapshot.targetJapanese)
        let whisperPercent = compareMatchPercent(heard: snapshot.whisperText, target: snapshot.targetJapanese)

        let onDeviceLabel = UILabel()
        onDeviceLabel.numberOfLines = 0
        onDeviceLabel.attributedText = compareRecapEngineRow(
            title: "On Device",
            heard: snapshot.onDeviceText,
            percent: onDevicePercent,
            isBest: onDevicePercent > whisperPercent && onDevicePercent > 0
        )

        let whisperLabel = UILabel()
        whisperLabel.numberOfLines = 0
        whisperLabel.attributedText = compareRecapEngineRow(
            title: "GPT Whisper",
            heard: snapshot.whisperText,
            percent: whisperPercent,
            isBest: whisperPercent > onDevicePercent && whisperPercent > 0
        )

        stack.addArrangedSubview(targetLabel)
        stack.addArrangedSubview(onDeviceLabel)
        stack.addArrangedSubview(whisperLabel)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func compareRecapEngineRow(
        title: String,
        heard: String,
        percent: Int,
        isBest: Bool
    ) -> NSAttributedString {
        let heardText = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = heardText.isEmpty ? "—" : heardText
        let marker = isBest ? "  ✓" : ""

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "\(title)  \(percent)%\(marker)\n",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: isBest ? UIColor.systemGreen : UIColor.secondaryLabel,
            ]
        ))
        text.append(NSAttributedString(
            string: body,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.label,
            ]
        ))
        return text
    }

    private func compareMatchPercent(heard: String, target: String) -> Int {
        guard !target.isEmpty else { return 0 }
        let match = RolePlaySpeechMatching.evaluate(heard: heard, target: target, alreadyMatched: 0)
        let total = max(RolePlaySpeechMatching.normalizeForMatch(target).count, 1)
        return Int((Double(match.matchedNormalizedCount) / Double(total) * 100).rounded())
    }
}
