//
//  DialogueQuizQuestionView.swift
//  shizen
//
//  Single comprehension-quiz question (prompt + choices + evidence line).
//

import InteractionKit
import UIKit

final class DialogueQuizQuestionView: UIView {

    private static let choiceChrome = KanaChoiceButton.Chrome(
        cornerRadius: 8,
        normalBorderWidth: 1,
        emphasisBorderWidth: 2,
        contentInsets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    )

    /// Extra inset so the prompt wraps inside the choice column.
    private static let promptHorizontalInset: CGFloat = 20

    private let question: DialogueQuizQuestion
    private let numberLabel = UILabel()
    private let promptWrap = UIView()
    private let promptLabel = FuriganaTranscriptLabel()
    private let targetLabel = FuriganaTranscriptLabel()
    private let choicesStack = UIStackView()
    private let explainerLabel = FuriganaTranscriptLabel()
    private let resultLabel = UILabel()
    private let evidenceStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var selectedButton: KanaChoiceButton?
    private var hasRevealedResult = false
    private var sourceLines: [DialogueQuizSourceLine] = []
    private var evidenceRow: DialogueQuizEvidenceRowView?

    var hasSelection: Bool { selectedButton != nil }
    var selectedChoiceView: UIView? { selectedButton }
    var isSelectionCorrect: Bool {
        guard let selectedButton else { return false }
        return valuesMatch(selectedButton.value, question.correctChoice)
    }
    var onSelectionChanged: (() -> Void)?
    /// Fired after a reveal changes height (wrong choices collapse and/or evidence appears).
    var onRevealContentDidChange: (() -> Void)?
    /// Right-swipe on an evidence bubble — host pushes sentence scrub.
    var onFocusEvidenceLine: ((DialogueQuizSourceLine) -> Void)?
    var hostScrollView: UIScrollView? {
        didSet { evidenceRow?.hostScrollView = hostScrollView }
    }
    var showsQuestionEyebrow: Bool {
        get { !numberLabel.isHidden }
        set { numberLabel.isHidden = !newValue }
    }

    init(
        questionNumber: Int,
        question: DialogueQuizQuestion,
        choiceHeight: CGFloat,
        questionCount: Int? = nil,
        showsQuestionNumber: Bool = true,
        sourceLines: [DialogueQuizSourceLine] = []
    ) {
        self.question = question
        self.sourceLines = sourceLines
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        configureLabels(
            questionNumber: questionNumber,
            questionCount: questionCount,
            showsQuestionNumber: showsQuestionNumber
        )
        configureChoices(choiceHeight: choiceHeight)
        configureEvidence()
        installLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLabels(
        questionNumber: Int,
        questionCount: Int?,
        showsQuestionNumber: Bool
    ) {
        if showsQuestionNumber {
            if let questionCount, questionCount > 0 {
                numberLabel.text = "Question \(questionNumber) of \(questionCount)"
            } else {
                numberLabel.text = "Question \(questionNumber)."
            }
        } else {
            numberLabel.text = "Quick check"
        }
        numberLabel.font = .preferredFont(forTextStyle: .footnote)
        numberLabel.textColor = .secondaryLabel
        numberLabel.textAlignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        configureQuizTextLabel(
            promptLabel,
            text: question.prompt,
            font: .preferredFont(forTextStyle: .title3).bold(),
            textColor: .label
        )

        configureTargetLabel()

        configureQuizTextLabel(
            explainerLabel,
            text: question.wrongAnswerExplanation,
            font: .preferredFont(forTextStyle: .subheadline),
            textColor: .secondaryLabel
        )
        explainerLabel.isHidden = true

        resultLabel.font = .preferredFont(forTextStyle: .subheadline).bold()
        resultLabel.textColor = .secondaryLabel
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.isHidden = true
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureQuizTextLabel(
        _ label: FuriganaTranscriptLabel,
        text: String,
        font: UIFont,
        textColor: UIColor
    ) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.clipsToBounds = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.verticalTextInsetsAffectAlignmentRect = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.containsKanji(trimmed) else {
            label.textInsets = .zero
            label.attributedText = nil
            label.font = font
            label.text = text
            label.textColor = textColor
            return
        }

        let attributed = JapaneseFuriganaBuilder.wrappingScenarioAttributedString(
            for: trimmed,
            font: font,
            textColor: textColor
        )
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: label,
            attributed: Self.centeredAttributedString(attributed),
            contentInsets: JapaneseFuriganaBuilder.compactDisplayInsets(for: font)
        )
    }

    private func configureTargetLabel() {
        let trimmed = question.target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        targetLabel.isHidden = trimmed.isEmpty
        configureQuizTextLabel(
            targetLabel,
            text: trimmed,
            font: .preferredFont(forTextStyle: .title2).bold(),
            textColor: .label
        )
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func centeredAttributedString(_ attributed: NSAttributedString) -> NSAttributedString {
        let centered = NSMutableAttributedString(attributedString: attributed)
        guard centered.length > 0 else { return centered }
        let font = centered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            ?? .preferredFont(forTextStyle: .title3)
        let style = NSMutableParagraphStyle()
        style.setParagraphStyle(JapaneseFuriganaBuilder.wrappingFuriganaParagraphStyle(font: font))
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        centered.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: centered.length)
        )
        return centered
    }

    private func configureChoices(choiceHeight: CGFloat) {
        choicesStack.axis = .vertical
        choicesStack.spacing = question.layout == .grid ? 8 : 10
        choicesStack.translatesAutoresizingMaskIntoConstraints = false

        let shuffledChoices = question.choices.shuffled()
        switch question.layout {
        case .grid:
            choiceButtons = LessonChoiceGrid.rebuild(
                in: choicesStack,
                choices: shuffledChoices,
                labelStyle: .compact,
                spacing: 8,
                target: self,
                action: #selector(choiceTapped(_:)),
                preferredHeight: choiceHeight,
                chrome: Self.choiceChrome
            )
        case .list:
            choiceButtons = LessonChoiceList.rebuild(
                in: choicesStack,
                choices: shuffledChoices,
                labelStyle: .compact,
                spacing: 10,
                target: self,
                action: #selector(choiceTapped(_:)),
                chrome: Self.choiceChrome
            )
        }
    }

    private func configureEvidence() {
        evidenceStack.axis = .vertical
        evidenceStack.alignment = .fill
        evidenceStack.spacing = 16
        evidenceStack.isHidden = true
        evidenceStack.translatesAutoresizingMaskIntoConstraints = false

        guard !sourceLines.isEmpty else { return }

        let row = DialogueQuizEvidenceRowView(lines: sourceLines)
        row.hostScrollView = hostScrollView
        row.onFocusLine = { [weak self] line in
            self?.onFocusEvidenceLine?(line)
        }
        evidenceRow = row
        evidenceStack.addArrangedSubview(row)
    }

    var evidenceSwipeContainers: [DialogueBubbleSwipeRevealContainer] {
        evidenceRow?.swipeContainers ?? []
    }

    func configureEvidenceSwipeDeferral(
        pagingScrollView: UIScrollView?,
        from viewController: UIViewController?
    ) {
        for container in evidenceSwipeContainers {
            if let pagingScrollView {
                pagingScrollView.panGestureRecognizer.require(toFail: container.panGestureRecognizer)
            }
            container.configureContentPopGestureDeferral(from: viewController)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreferredMaxLayoutWidth(
            for: promptLabel,
            availableWidth: promptWrap.bounds.width - 2 * Self.promptHorizontalInset
        )
        updatePreferredMaxLayoutWidth(
            for: explainerLabel,
            availableWidth: explainerLabel.bounds.width
        )
    }

    private func updatePreferredMaxLayoutWidth(
        for label: FuriganaTranscriptLabel,
        availableWidth: CGFloat
    ) {
        let width = max(0, availableWidth)
        guard width > 0, abs(label.preferredMaxLayoutWidth - width) > 0.5 else { return }
        label.preferredMaxLayoutWidth = width
    }

    private func installLayout() {
        promptWrap.translatesAutoresizingMaskIntoConstraints = false
        promptWrap.addSubview(promptLabel)
        NSLayoutConstraint.activate([
            promptLabel.topAnchor.constraint(equalTo: promptWrap.topAnchor),
            promptLabel.bottomAnchor.constraint(equalTo: promptWrap.bottomAnchor),
            promptLabel.leadingAnchor.constraint(
                equalTo: promptWrap.leadingAnchor,
                constant: Self.promptHorizontalInset
            ),
            promptLabel.trailingAnchor.constraint(
                equalTo: promptWrap.trailingAnchor,
                constant: -Self.promptHorizontalInset
            ),
        ])

        let stack = UIStackView(arrangedSubviews: [
            numberLabel,
            promptWrap,
            targetLabel,
            choicesStack,
            resultLabel,
            explainerLabel,
            evidenceStack,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(12, after: numberLabel)
        if targetLabel.isHidden {
            stack.setCustomSpacing(20, after: promptWrap)
        } else {
            stack.setCustomSpacing(12, after: promptWrap)
            stack.setCustomSpacing(20, after: targetLabel)
        }
        stack.setCustomSpacing(16, after: choicesStack)
        stack.setCustomSpacing(12, after: resultLabel)
        stack.setCustomSpacing(20, after: explainerLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        guard !hasRevealedResult else { return }

        selectedButton = sender
        for button in choiceButtons {
            button.setChosen(button === sender)
        }
        revealResult()
        onSelectionChanged?()
    }

    func revealResult() {
        guard !hasRevealedResult, let selectedButton else { return }
        hasRevealedResult = true
        lockChoices()

        if isSelectionCorrect {
            selectedButton.applySuccessAppearance()
            fadeOutIncorrectChoices { [weak self] in
                self?.revealEvidenceIfNeeded()
            }
        } else {
            selectedButton.applyIncorrectAppearance()
            if !question.wrongAnswerExplanation.isEmpty {
                explainerLabel.isHidden = false
            }
            revealEvidenceIfNeeded()
        }
    }

    /// Result line used to bring newly revealed evidence on-screen if it overflows.
    var revealedEvidenceScrollTarget: UIView? {
        resultLabel.isHidden ? nil : resultLabel
    }

    /// First evidence bubble, if the reveal is showing spoken lines.
    var revealedEvidencePeekTarget: UIView? {
        evidenceStack.isHidden ? nil : evidenceRow?.firstLineView
    }

    /// Spoken evidence lines shown after the answer (0 when the question has none).
    var evidenceLineCount: Int { sourceLines.count }

    /// Full evidence row for a spoken catalog index, including English under the bubble.
    func evidenceLineView(forSpokenIndex spokenIndex: Int) -> UIView? {
        evidenceStack.isHidden ? nil : evidenceRow?.lineView(forSpokenIndex: spokenIndex)
    }

    /// Runs `body` against the evidence's resting layout, ignoring entrance transforms.
    func withSettledEvidenceLayout(_ body: () -> Void) {
        evidenceRow?.withSettledLineTransforms(body) ?? body()
    }

    func setPlayingSpokenIndex(_ spokenIndex: Int?) {
        evidenceRow?.setPlayingSpokenIndex(spokenIndex)
    }

    func applyEvidenceKaraoke(tokenSync: DialogueTokenSync?, time: TimeInterval) {
        evidenceRow?.applyKaraoke(tokenSync: tokenSync, time: time)
    }

    private func fadeOutIncorrectChoices(then completion: @escaping () -> Void) {
        let outgoing = choiceButtons.filter { $0 !== selectedButton }
        let finish = {
            self.hideIncorrectChoices()
            self.layoutIfNeeded()
            completion()
        }
        guard !outgoing.isEmpty, window != nil else {
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.16,
            delay: 0.06,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            for button in outgoing {
                button.alpha = 0
            }
        } completion: { _ in
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.hideIncorrectChoices()
                self.layoutIfNeeded()
            } completion: { _ in
                completion()
            }
        }
    }

    private func hideIncorrectChoices() {
        for button in choiceButtons where button !== selectedButton {
            button.alpha = 0
            button.isHidden = true
        }
        for row in choicesStack.arrangedSubviews {
            guard let stack = row as? UIStackView else { continue }
            if stack.arrangedSubviews.allSatisfy(\.isHidden) {
                stack.isHidden = true
            }
        }
    }

    private func revealEvidenceIfNeeded() {
        if !sourceLines.isEmpty {
            resultLabel.text = isSelectionCorrect
                ? "Correct! See below..."
                : "That's incorrect, see below."
            resultLabel.isHidden = false
            evidenceStack.isHidden = false
            layoutIfNeeded()
            prepareEvidenceEntrance()
            playEvidenceEntrance()
        }
        onRevealContentDidChange?()
    }

    private func prepareEvidenceEntrance() {
        resultLabel.alpha = 0
        resultLabel.transform = CGAffineTransform(translationX: 0, y: 16)
        evidenceRow?.prepareEntrance()
    }

    private func playEvidenceEntrance() {
        let settle = {
            self.resultLabel.alpha = 1
            self.resultLabel.transform = .identity
            self.evidenceRow?.settleEntrance()
        }
        guard window != nil else {
            settle()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.resultLabel.alpha = 1
            self.resultLabel.transform = .identity
        }
        evidenceRow?.playEntrance()
    }

    private func lockChoices() {
        for button in choiceButtons {
            button.isUserInteractionEnabled = false
        }
    }

    private func valuesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Transcript-style evidence: A/B sides, English under each bubble, playback scale.
private final class DialogueQuizEvidenceRowView: UIView {

    private static let japaneseFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title2)
        return .systemFont(ofSize: base.pointSize, weight: .medium)
    }()

    var onFocusLine: ((DialogueQuizSourceLine) -> Void)?
    var hostScrollView: UIScrollView? {
        didSet { swipeContainers.forEach { $0.hostScrollView = hostScrollView } }
    }

    private(set) var swipeContainers: [DialogueBubbleSwipeRevealContainer] = []
    private(set) var firstLineView: UIView?
    private var items: [LineItem] = []
    private var playingSpokenIndex: Int?
    private var appliedKaraokeTokens: [Int] = []

    func lineView(forSpokenIndex spokenIndex: Int) -> UIView? {
        items.first { $0.line.spokenIndex == spokenIndex }?.row
    }

    func withSettledLineTransforms(_ body: () -> Void) {
        let transforms = items.map(\.row.transform)
        items.forEach { $0.row.transform = .identity }
        body()
        for (item, transform) in zip(items, transforms) {
            item.row.transform = transform
        }
    }

    func prepareEntrance() {
        for item in items {
            item.row.alpha = 0
            item.row.transform = CGAffineTransform(translationX: 0, y: entranceOffset(for: item.row))
        }
    }

    func playEntrance() {
        for (index, item) in items.enumerated() {
            UIView.animate(
                withDuration: 0.36,
                delay: 0.05 + 0.07 * TimeInterval(index),
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.72,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                item.row.alpha = 1
                item.row.transform = .identity
            }
        }
    }

    func settleEntrance() {
        for item in items {
            item.row.alpha = 1
            item.row.transform = .identity
        }
    }

    private func entranceOffset(for view: UIView) -> CGFloat {
        if let window {
            let frame = view.convert(view.bounds, to: window)
            return max(window.bounds.maxY - frame.minY + 24, 140)
        }
        return 180
    }

    init(lines: [DialogueQuizSourceLine]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        install(lines: lines)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayingSpokenIndex(_ spokenIndex: Int?) {
        playingSpokenIndex = spokenIndex
        layoutIfNeeded()
        let apply = {
            for item in self.items {
                let emphasis: CGFloat = item.line.spokenIndex == spokenIndex ? 1 : 0
                item.bubble.setEmphasis(emphasis)
                DialogueBubbleLayout.applyBubbleEmphasisTransform(
                    to: item.bubble,
                    emphasis: emphasis,
                    side: item.line.speakerSide
                )
            }
        }
        guard window != nil else {
            apply()
            return
        }
        UIView.animate(
            withDuration: DialogueBubbleLayout.emphasisDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
            animations: apply
        )
    }

    func applyKaraoke(tokenSync: DialogueTokenSync?, time: TimeInterval) {
        let sync = ExperimentSettings.dialogueShowsTokenSync ? tokenSync : nil
        if appliedKaraokeTokens.count != items.count {
            appliedKaraokeTokens = Array(repeating: -1, count: items.count)
        }
        let fullHeight = ExperimentSettings.dialogueTokenSyncHighlightStyle == .full
        let fullHeightBit = fullHeight ? 10_000 : 0
        for (index, item) in items.enumerated() {
            let isActive = item.line.spokenIndex == playingSpokenIndex
            let tokenIndex = isActive ? sync?.tokenIndex(lineIndex: item.line.spokenIndex, at: time) : nil
            let key = (tokenIndex ?? -1) + fullHeightBit
            guard key != appliedKaraokeTokens[index] else { continue }
            appliedKaraokeTokens[index] = key
            if let tokenIndex,
               let range = sync?.utf16Range(
                lineIndex: item.line.spokenIndex,
                tokenIndex: tokenIndex,
                inDisplay: item.bubble.label.attributedText?.string ?? ""
               ) {
                item.bubble.label.setTokenHighlightPreservingLayout(
                    foregroundColor: .label,
                    highlightedRange: range,
                    fullHeight: fullHeight,
                    highlightColor: item.bubble.tokenHighlightColor
                )
            } else {
                item.bubble.label.setForegroundColorPreservingLayout(.label)
            }
        }
    }

    private func install(lines: [DialogueQuizSourceLine]) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DialogueBubbleLayout.sameSpeakerSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        appliedKaraokeTokens = Array(repeating: -1, count: lines.count)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        var previousSpeaker: String?
        for (index, line) in lines.enumerated() {
            let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let showsSpeaker = !speaker.isEmpty && speaker != previousSpeaker
            if !speaker.isEmpty {
                previousSpeaker = speaker
            }
            let item = makeLineItem(for: line, showsSpeakerLabel: showsSpeaker)
            stack.addArrangedSubview(item.row)
            items.append(item)
            if firstLineView == nil {
                firstLineView = item.row
            }
            if index > 0 {
                let previous = lines[index - 1]
                let spacing = DialogueBubbleLayout.spacingAfterSpokenLine(
                    previousSpeaker: previous.speaker,
                    nextSpeaker: line.speaker
                )
                stack.setCustomSpacing(spacing, after: stack.arrangedSubviews[index - 1])
            }
        }
    }

    private func makeLineItem(
        for line: DialogueQuizSourceLine,
        showsSpeakerLabel: Bool
    ) -> LineItem {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.clipsToBounds = false

        let column = UIStackView()
        column.axis = .vertical
        column.alignment = line.speakerSide == .leading ? .leading : .trailing
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false

        var speakerLabel: UILabel?
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        if showsSpeakerLabel, !speaker.isEmpty {
            let label = UILabel()
            label.font = GrammarJapaneseTypography.scenarioSpeakerFont
            label.textColor = .secondaryLabel
            label.textAlignment = line.speakerSide == .trailing ? .right : .left
            label.numberOfLines = 1
            label.adjustsFontForContentSizeCategory = true
            label.text = "\(speaker):"
            speakerLabel = label
            column.addArrangedSubview(
                DialogueBubbleLayout.insetMetadataWrapper(around: label, side: line.speakerSide)
            )
        }

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.lineBreakMode = .byWordWrapping
        japaneseLabel.textAlignment = .natural
        japaneseLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        japaneseLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: japaneseLabel,
            text: line.japanese,
            font: Self.japaneseFont,
            textColor: .label
        )

        let bubble = DialogueJapaneseBubbleView(label: japaneseLabel)
        bubble.setBackgroundStyle(.glass)
        bubble.setUnderglowConfiguration(.forSpeaker(line.speakerSide))
        bubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let swipeContainer = DialogueBubbleSwipeRevealContainer(bubbleView: bubble)
        swipeContainer.hostScrollView = hostScrollView
        swipeContainer.chromeEdge = line.speakerSide == .leading ? .trailing : .leading
        swipeContainer.allowsExpand = true
        swipeContainer.allowsProgressiveReveal = false
        swipeContainer.onCommit = { [weak self] in
            self?.onFocusLine?(line)
        }
        swipeContainers.append(swipeContainer)

        column.addArrangedSubview(swipeContainer)
        if let speakerView = column.arrangedSubviews.first, speakerLabel != nil {
            column.setCustomSpacing(4, after: speakerView)
        }
        swipeContainer.alignChromeBottom(to: speakerLabel)

        let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !english.isEmpty {
            let englishLabel = UILabel()
            englishLabel.font = .preferredFont(forTextStyle: .subheadline)
            englishLabel.textColor = .secondaryLabel
            englishLabel.textAlignment = line.speakerSide == .trailing ? .right : .left
            englishLabel.numberOfLines = 0
            englishLabel.adjustsFontForContentSizeCategory = true
            englishLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            englishLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            englishLabel.text = english
            column.addArrangedSubview(
                DialogueBubbleLayout.insetMetadataWrapper(around: englishLabel, side: line.speakerSide)
            )
        }

        row.addSubview(column)
        DialogueBubbleLayout.pinMessageColumn(column, to: row, side: line.speakerSide)

        return LineItem(line: line, row: row, bubble: bubble)
    }
}

private struct LineItem {
    let line: DialogueQuizSourceLine
    let row: UIView
    let bubble: DialogueJapaneseBubbleView
}
