//
//  DialogueGrammarUsageCardView.swift
//  shizen
//
//  "How to use" card on the grammar pattern screen.
//  Same surface and motion as the Deeper Meaning card.
//

import InteractionKit
import UIKit

final class DialogueGrammarUsageCardView: UIView {

    enum State {
        case loading
        case result(GeminiGrammarUsage.Result, feedback: LLMFeedbackReceipt?)
        case catalog(shortMeaning: String, formNote: String)
        case unavailable(String)
        case failed(String)
    }

    private let surface = GlossCardSurfaceView()
    private let sectionStack = UIStackView()
    private let sectionTitle = UILabel()
    private let loadingRow = UIStackView()
    private let loadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let loadingLabel = UILabel()
    private let headlineLabel = UILabel()
    private let formLabel = UILabel()
    private let examplesLabel = UILabel()
    private let noteLabel = UILabel()
    private let messageLabel = UILabel()
    private let explainTitle = UILabel()
    private let explainLoadingRow = UIStackView()
    private let explainLoadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let explainLoadingLabel = UILabel()
    private let explainHeadline = UILabel()
    private let explainForm = UILabel()
    private let explainNote = UILabel()
    private let explainButton = UIButton(type: .system)
    private let examplesButton = UIButton(type: .system)
    private let edgeButtonStack = UIStackView()
    private let feedbackRow = LLMFeedbackRow()

    var onExplain: (() -> Void)?
    var onExamples: (() -> Void)?

    private static let contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let shadowBleed: CGFloat = 12
    private static let accentColor = UIColor.systemYellow
    private static let edgeControlLift: CGFloat = 8
    private static let thumbsOverlap: CGFloat = 18
    private static let explainButtonOverlap: CGFloat = 18

    private var sectionBottomConstraint: NSLayoutConstraint?
    private var surfaceBottomConstraint: NSLayoutConstraint?
    /// Offered thumbs whose space is already reserved but which appear only after the card settles.
    private var pendingFeedback: LLMFeedbackReceipt?
    private var explainAvailable = false
    private var explainEngaged = false
    private var examplesAvailable = false
    private var examplesEngaged = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    /// Swaps content with a short crossfade when the card is on screen. Thumbs for a
    /// result wait for `presentPendingFeedback()`.
    func apply(_ state: State) {
        let onScreen = !isHidden && window != nil
        GlossMotion.crossfade(sectionStack, animated: onScreen) {
            applyContent(state)
        }
    }

    func presentPendingFeedback(ignoreCadence: Bool = false) {
        guard let feedback = pendingFeedback else { return }
        pendingFeedback = nil
        feedbackRow.present(feedback, ignoreCadence: ignoreCadence)
        updateEdgeChrome()
    }

    func setExplainAvailable(_ available: Bool) {
        explainAvailable = available
        explainButton.isHidden = !available
        if !available {
            explainEngaged = false
            hideExplainContent()
        }
        applyExplainButtonChrome()
        updateEdgeChrome()
    }

    var isExplainEngaged: Bool { explainEngaged }
    var isExamplesEngaged: Bool { examplesEngaged }

    func setExplainEngaged(_ engaged: Bool) {
        explainEngaged = engaged
        if !engaged { hideExplainContent() }
        applyExplainButtonChrome()
        updateEdgeChrome()
    }

    func setExamplesAvailable(_ available: Bool) {
        examplesAvailable = available
        examplesButton.isHidden = !available
        if !available { examplesEngaged = false }
        applyExamplesButtonChrome()
        updateEdgeChrome()
    }

    func setExamplesEngaged(_ engaged: Bool) {
        examplesEngaged = engaged && examplesAvailable
        applyExamplesButtonChrome()
        updateEdgeChrome()
    }

    func applyExplainLoading() {
        explainTitle.isHidden = true
        explainHeadline.isHidden = true
        explainForm.isHidden = true
        explainNote.isHidden = true
        explainLoadingRow.isHidden = false
        explainLoadingSpinner.isHidden = false
        explainLoadingSpinner.reset()
        updateEdgeChrome()
        setNeedsLayout()
    }

    func applyExplainResult(_ result: GeminiGrammarUsage.Result, feedback: LLMFeedbackReceipt? = nil) {
        explainLoadingRow.isHidden = true
        explainLoadingSpinner.isHidden = true
        explainTitle.text = "IN THIS SCENE"
        explainTitle.isHidden = false
        setText(explainHeadline, glossWithoutVerbLabel(result.inThisScene))
        setAttributed(explainForm, Self.attributedForm(result.form))
        setText(explainNote, result.note)
        if let feedback {
            pendingFeedback = feedback
        }
        updateEdgeChrome()
        setNeedsLayout()
    }

    func offerFeedback(_ feedback: LLMFeedbackReceipt?) {
        guard let feedback else { return }
        pendingFeedback = feedback
        updateEdgeChrome()
    }

    func applyExplainFailed(_ message: String) {
        explainLoadingRow.isHidden = true
        explainLoadingSpinner.isHidden = true
        explainTitle.isHidden = true
        explainHeadline.isHidden = true
        explainForm.isHidden = true
        setText(explainNote, message)
        updateEdgeChrome()
        setNeedsLayout()
    }

    private func hideExplainContent() {
        explainLoadingRow.isHidden = true
        explainLoadingSpinner.isHidden = true
        explainTitle.isHidden = true
        explainHeadline.isHidden = true
        explainForm.isHidden = true
        explainNote.isHidden = true
    }

    private func applyContent(_ state: State) {
        pendingFeedback = nil
        let resultLabels = [headlineLabel, formLabel, examplesLabel, noteLabel]
        switch state {
        case .loading:
            loadingRow.isHidden = false
            loadingSpinner.isHidden = false
            loadingSpinner.reset()
            resultLabels.forEach { $0.isHidden = true }
            messageLabel.isHidden = true
            hideExplainContent()
            feedbackRow.dismiss()
        case .result(let result, let feedback):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            messageLabel.isHidden = true
            hideExplainContent()
            setText(headlineLabel, glossWithoutVerbLabel(result.inThisScene))
            setAttributed(formLabel, Self.attributedForm(result.form))
            let examples = result.examples.map { "· \($0)" }.joined(separator: "\n")
            setAttributed(examplesLabel, Self.attributedExamples(examples))
            setText(noteLabel, result.note)
            if let feedback, LLMFeedbackPrompt.shouldOffer(feedback) {
                pendingFeedback = feedback
            } else {
                feedbackRow.dismiss()
            }
        case .catalog(let shortMeaning, let formNote):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            messageLabel.isHidden = true
            examplesLabel.isHidden = true
            noteLabel.isHidden = true
            feedbackRow.dismiss()
            if !explainEngaged { hideExplainContent() }
            setText(headlineLabel, shortMeaning)
            setAttributed(formLabel, Self.attributedForm(formNote))
        case .unavailable(let message), .failed(let message):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            resultLabels.forEach { $0.isHidden = true }
            hideExplainContent()
            feedbackRow.dismiss()
            setText(messageLabel, message)
        }
        updateEdgeChrome()
        setNeedsLayout()
    }

    private func setText(_ label: UILabel, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        label.text = trimmed.isEmpty ? nil : trimmed
        label.isHidden = trimmed.isEmpty
    }

    private func setAttributed(_ label: UILabel, _ text: NSAttributedString?) {
        label.attributedText = text
        label.isHidden = text == nil
    }

    /// Japanese in the formula reads in the primary color, the slot words stay secondary.
    private static func attributedForm(_ form: String) -> NSAttributedString? {
        let trimmed = form.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let attributed = NSMutableAttributedString(string: trimmed, attributes: [
            .font: baseFont,
            .foregroundColor: UIColor.secondaryLabel,
        ])
        let japaneseFont = baseFont.bold()
        var utf16 = 0
        for character in trimmed {
            let length = character.utf16.count
            if character.unicodeScalars.contains(where: isJapanese) {
                attributed.addAttributes(
                    [.font: japaneseFont, .foregroundColor: UIColor.label],
                    range: NSRange(location: utf16, length: length)
                )
            }
            utf16 += length
        }
        return attributed
    }

    private static func attributedExamples(_ text: String) -> NSAttributedString? {
        guard !text.isEmpty else { return nil }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph,
        ])
    }

    private static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3005:
            return true
        default:
            return false
        }
    }

    private func setupUI() {
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        sectionTitle.text = "HOW TO USE"
        sectionTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        sectionTitle.textColor = .secondaryLabel

        headlineLabel.font = UIFont.preferredFont(forTextStyle: .title3).bold()
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 0

        for label in [formLabel, examplesLabel, noteLabel, messageLabel, explainForm, explainNote] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.isHidden = true
        }

        explainTitle.text = "IN THIS SCENE"
        explainTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        explainTitle.textColor = .secondaryLabel
        explainTitle.isHidden = true

        explainHeadline.font = UIFont.preferredFont(forTextStyle: .body).bold()
        explainHeadline.textColor = .label
        explainHeadline.numberOfLines = 0
        explainHeadline.isHidden = true

        explainLoadingSpinner.configure(with: Self.accentColor)
        explainLoadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            explainLoadingSpinner.widthAnchor.constraint(equalToConstant: 24),
            explainLoadingSpinner.heightAnchor.constraint(equalToConstant: 24),
        ])
        explainLoadingLabel.text = "Analyzing…"
        explainLoadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        explainLoadingLabel.textColor = .secondaryLabel
        explainLoadingRow.axis = .horizontal
        explainLoadingRow.alignment = .center
        explainLoadingRow.spacing = 10
        explainLoadingRow.isHidden = true
        explainLoadingRow.addArrangedSubview(explainLoadingSpinner)
        explainLoadingRow.addArrangedSubview(explainLoadingLabel)

        configureExplainButton()
        configureExamplesButton()
        configureEdgeButtonStack()

        loadingSpinner.configure(with: Self.accentColor)
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingSpinner.widthAnchor.constraint(equalToConstant: 24),
            loadingSpinner.heightAnchor.constraint(equalToConstant: 24),
        ])

        loadingLabel.text = "Analyzing…"
        loadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        loadingLabel.textColor = .secondaryLabel
        loadingLabel.numberOfLines = 1

        loadingRow.axis = .horizontal
        loadingRow.alignment = .center
        loadingRow.spacing = 10
        loadingRow.addArrangedSubview(loadingSpinner)
        loadingRow.addArrangedSubview(loadingLabel)

        sectionStack.axis = .vertical
        sectionStack.alignment = .fill
        sectionStack.spacing = 6
        [sectionTitle, loadingRow, headlineLabel, formLabel, examplesLabel, noteLabel, messageLabel,
         explainTitle, explainLoadingRow, explainHeadline, explainForm, explainNote]
            .forEach { sectionStack.addArrangedSubview($0) }
        sectionStack.setCustomSpacing(8, after: formLabel)
        sectionStack.setCustomSpacing(8, after: examplesLabel)
        sectionStack.setCustomSpacing(6, after: explainTitle)
        sectionStack.setCustomSpacing(12, after: explainNote)
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        surface.backgroundColor = .secondarySystemGroupedBackground
        surface.layer.cornerRadius = 14
        surface.layer.cornerCurve = .continuous
        surface.layer.shadowColor = UIColor.black.cgColor
        surface.layer.shadowOpacity = 0.14
        surface.layer.shadowRadius = 10
        surface.layer.shadowOffset = CGSize(width: 0, height: 4)
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(sectionStack)
        addSubview(surface)
        addSubview(edgeButtonStack)
        addSubview(feedbackRow)
        feedbackRow.onVisibilityChange = { [weak self] in
            self?.updateEdgeChrome()
        }

        let insets = Self.contentInsets
        let sectionBottom = sectionStack.bottomAnchor.constraint(
            equalTo: surface.bottomAnchor,
            constant: -insets.bottom
        )
        sectionBottomConstraint = sectionBottom
        let surfaceBottom = surface.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Self.shadowBleed
        )
        surfaceBottomConstraint = surfaceBottom
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceBottom,

            sectionStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: insets.top),
            sectionStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: insets.left),
            sectionStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -insets.right),
            sectionBottom,

            edgeButtonStack.centerYAnchor.constraint(
                equalTo: surface.bottomAnchor,
                constant: -Self.edgeControlLift
            ),
            edgeButtonStack.leadingAnchor.constraint(
                equalTo: surface.leadingAnchor,
                constant: insets.left
            ),
            edgeButtonStack.trailingAnchor.constraint(
                lessThanOrEqualTo: feedbackRow.leadingAnchor,
                constant: -8
            ),

            feedbackRow.bottomAnchor.constraint(
                equalTo: surface.bottomAnchor,
                constant: LLMFeedbackRow.diameter / 2 - Self.edgeControlLift
            ),
            feedbackRow.trailingAnchor.constraint(
                equalTo: surface.trailingAnchor,
                constant: -insets.right
            ),
        ])

        applyContent(.loading)
    }

    private func configureExplainButton() {
        explainButton.isHidden = true
        explainButton.setContentHuggingPriority(.required, for: .horizontal)
        explainButton.setContentHuggingPriority(.required, for: .vertical)
        explainButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        explainButton.setContentCompressionResistancePriority(.required, for: .vertical)
        explainButton.translatesAutoresizingMaskIntoConstraints = false
        explainButton.addAction(UIAction { [weak self] _ in
            self?.onExplain?()
        }, for: .touchUpInside)
        applyExplainButtonChrome()
    }

    private func configureExamplesButton() {
        examplesButton.isHidden = true
        examplesButton.setContentHuggingPriority(.required, for: .horizontal)
        examplesButton.setContentHuggingPriority(.required, for: .vertical)
        examplesButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        examplesButton.setContentCompressionResistancePriority(.required, for: .vertical)
        examplesButton.translatesAutoresizingMaskIntoConstraints = false
        examplesButton.addAction(UIAction { [weak self] _ in
            self?.onExamples?()
        }, for: .touchUpInside)
        applyExamplesButtonChrome()
    }

    private func configureEdgeButtonStack() {
        edgeButtonStack.axis = .horizontal
        edgeButtonStack.alignment = .center
        edgeButtonStack.spacing = 8
        edgeButtonStack.translatesAutoresizingMaskIntoConstraints = false
        edgeButtonStack.addArrangedSubview(explainButton)
        edgeButtonStack.addArrangedSubview(examplesButton)
    }

    private func applyExamplesButtonChrome() {
        var config: UIButton.Configuration = examplesEngaged ? .filled() : .glass()
        config.cornerStyle = .capsule
        config.title = "Examples"
        config.image = UIImage(
            systemName: "list.bullet",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: examplesEngaged ? .semibold : .regular
            )
        )
        config.imagePlacement = .leading
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [examplesEngaged] incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: examplesEngaged ? .semibold : .regular)
            return outgoing
        }
        if examplesEngaged {
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        } else {
            config.baseForegroundColor = .label
        }
        examplesButton.configuration = config
        examplesButton.accessibilityLabel = "Examples"
        examplesButton.accessibilityHint = examplesEngaged
            ? "Hides example phrases"
            : "Shows example phrases using this pattern"
    }

    private func applyExplainButtonChrome() {
        var config: UIButton.Configuration = explainEngaged ? .filled() : .glass()
        config.cornerStyle = .capsule
        config.title = "About"
        config.image = UIImage(
            systemName: "text.quote",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: explainEngaged ? .semibold : .regular
            )
        )
        config.imagePlacement = .leading
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [explainEngaged] incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: explainEngaged ? .semibold : .regular)
            return outgoing
        }
        if explainEngaged {
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        } else {
            config.baseForegroundColor = .label
        }
        explainButton.configuration = config
        explainButton.accessibilityLabel = "About"
        explainButton.accessibilityHint = explainEngaged
            ? "Hides this extra explanation"
            : "Shows how this pattern is used in the scene"
    }

    private func updateEdgeChrome() {
        let showingThumbs = !feedbackRow.isHidden || pendingFeedback != nil
        let showingExplain = explainAvailable && !explainButton.isHidden
        let showingExamples = examplesAvailable && !examplesButton.isHidden
        let showsEdge = showingThumbs || showingExplain || showingExamples
        let overlap = showsEdge ? Self.explainButtonOverlap + Self.edgeControlLift : 0
        sectionBottomConstraint?.constant = -(Self.contentInsets.bottom + overlap)
        let bleed = showsEdge
            ? max(Self.shadowBleed, Self.explainButtonOverlap + 6)
            : Self.shadowBleed
        surfaceBottomConstraint?.constant = -bleed
        bringSubviewToFront(edgeButtonStack)
        bringSubviewToFront(feedbackRow)
    }
}

extension UIFont {
    fileprivate func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - Lesson highlight feedback / QA

enum LessonHighlightSupportSubject {
    case highlights(DialogueLearningHighlights)
    case grammar(DialogueGrammarPatternRef, displayLabel: String)
}

enum LessonContentQAIdentity {
    /// Best-effort Studio `{ collectionId, slug }` from a scenario id.
    static func parse(scenarioID: String, collectionID: String?) -> (collectionId: String, slug: String) {
        if let collectionID {
            let prefix = "\(collectionID)/"
            if scenarioID.hasPrefix(prefix) {
                let slug = String(scenarioID.dropFirst(prefix.count))
                if !slug.isEmpty, !slug.contains("/") {
                    return (collectionID, slug)
                }
            }
            if !scenarioID.contains("/") {
                return (collectionID, scenarioID)
            }
        }
        if let slash = scenarioID.firstIndex(of: "/") {
            let collectionId = String(scenarioID[..<slash])
            let slug = String(scenarioID[scenarioID.index(after: slash)...])
            if !collectionId.isEmpty, !slug.isEmpty, !slug.contains("/") {
                return (collectionId, slug)
            }
        }
        let fallbackCollection = collectionID ?? "dialogue"
        return (fallbackCollection, scenarioID)
    }
}

enum LessonHighlightSupportMenu {

    static let barButtonAccessibilityID = "lessonHighlightSupportMenu"

    static var canSendQANotes: Bool {
        ContentCMSClient.isConfigured && !ContentQAClientToken.resolved.isEmpty
    }

    static var hasAnyAction: Bool {
        LLMGatewayClient.isAvailable || canSendQANotes
    }

    static func makeMenu(
        scene: LessonDialogueSceneContext,
        subject: LessonHighlightSupportSubject,
        presenter: UIViewController
    ) -> UIMenu? {
        guard hasAnyAction else { return nil }

        var children: [UIMenuElement] = []

        if LLMGatewayClient.isAvailable {
            let feedback = UIAction(
                title: "Feedback",
                subtitle: qaFocusTitle(for: subject),
                image: UIImage(systemName: "text.bubble")
            ) { _ in
                presentFeedback(from: presenter, scene: scene, subject: subject)
            }
            children.append(feedback)
        }

        if canSendQANotes {
            let note = UIAction(
                title: "Note",
                subtitle: "Tags + Studio link for Shohei",
                image: UIImage(systemName: "square.and.pencil")
            ) { _ in
                presentQANote(from: presenter, scene: scene, subject: subject)
            }
            children.append(UIMenu(title: "QA", options: .displayInline, children: [note]))
        }

        guard !children.isEmpty else { return nil }
        return UIMenu(children: children)
    }

    static func makeBarButtonItem(
        scene: LessonDialogueSceneContext,
        subject: LessonHighlightSupportSubject,
        presenter: UIViewController
    ) -> UIBarButtonItem? {
        guard let menu = makeMenu(scene: scene, subject: subject, presenter: presenter) else { return nil }
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: menu
        )
        item.accessibilityLabel = "Feedback and QA"
        item.accessibilityIdentifier = barButtonAccessibilityID
        return item
    }

    static func presentFeedback(
        from presenter: UIViewController,
        scene: LessonDialogueSceneContext,
        subject: LessonHighlightSupportSubject
    ) {
        let focusTitle = qaFocusTitle(for: subject)
        let context = LessonIssueContext(
            collectionId: scene.collectionId,
            scenarioId: scene.scenarioId,
            publishedVariantId: scene.publishedVariantId,
            publishedContentHash: scene.publishedContentHash,
            page: .highlights,
            focusTitle: focusTitle,
            focusDetails: qaDetailLines(for: subject),
            sessionMode: scene.sessionMode,
            quizQuestionNumber: nil,
            tone: .feedback
        )
        LessonIssueReportViewController.present(from: presenter, context: context)
    }

    static func presentQANote(
        from presenter: UIViewController,
        scene: LessonDialogueSceneContext,
        subject: LessonHighlightSupportSubject
    ) {
        let focusTitle = qaFocusTitle(for: subject)
        DialogueContentQANoteViewController.present(
            from: presenter,
            source: .dialogue,
            sourceId: qaSourceId(scene: scene, subject: subject),
            focusTitle: focusTitle,
            focusDetailLines: qaDetailLines(for: subject),
            lessonTitle: scene.lessonTitle,
            lessonID: scene.lessonID,
            sceneTitle: scene.sceneTitle,
            sceneSlug: scene.scenarioId,
            studioLink: ContentCMSClient.studioScenarioEditorLink(
                collectionId: scene.collectionId,
                slug: scene.scenarioId
            )
        )
    }

    static func qaFocusTitle(for subject: LessonHighlightSupportSubject) -> String {
        switch subject {
        case .highlights:
            return "Lesson highlights"
        case .grammar(_, let displayLabel):
            return "Grammar: \(displayLabel)"
        }
    }

    static func qaDetailLines(for subject: LessonHighlightSupportSubject) -> [String] {
        switch subject {
        case .highlights(let highlights):
            return highlightsDetailLines(highlights)
        case .grammar(let pattern, let displayLabel):
            return grammarDetailLines(pattern: pattern, displayLabel: displayLabel)
        }
    }

    static func highlightsDetailLines(_ highlights: DialogueLearningHighlights) -> [String] {
        var details: [String] = []
        if highlights.vocabulary.isEmpty {
            details.append("Vocab: none authored")
        } else {
            let preview = highlights.vocabulary.prefix(10).joined(separator: ", ")
            let suffix = highlights.vocabulary.count > 10 ? "…" : ""
            details.append("Vocab (\(highlights.vocabulary.count)): \(preview)\(suffix)")
        }
        if highlights.grammarPatterns.isEmpty {
            details.append("Grammar: none authored")
        } else {
            let labels = highlights.grammarPatternLabels.prefix(6).joined(separator: ", ")
            let suffix = highlights.grammarPatterns.count > 6 ? "…" : ""
            details.append("Grammar (\(highlights.grammarPatterns.count)): \(labels)\(suffix)")
        }
        if highlights.contextNotes.isEmpty {
            details.append("Context notes: none")
        } else {
            details.append("Context notes: \(highlights.contextNotes.count)")
            if let first = highlights.contextNotes.first {
                details.append("First note: \(trimmedExportText(first))")
            }
        }
        return details
    }

    static func grammarDetailLines(pattern: DialogueGrammarPatternRef, displayLabel: String) -> [String] {
        var lines = ["Pattern label: \(displayLabel)"]
        if let patternId = pattern.patternId {
            lines.append("patternId: \(patternId)")
        }
        if let grammarPointID = pattern.grammarPointID {
            lines.append("grammarPointID: \(grammarPointID)")
        }
        if let start = pattern.sourceSpokenStart {
            if let end = pattern.sourceSpokenEnd, end != start {
                lines.append("Scene lines (spoken): \(start)–\(end)")
            } else {
                lines.append("Scene line (spoken): \(start)")
            }
        }
        return lines
    }

    static func qaSourceId(scene: LessonDialogueSceneContext, subject: LessonHighlightSupportSubject) -> String {
        var id = "\(scene.collectionId)/\(scene.scenarioId)"
        switch subject {
        case .highlights:
            id += "#highlights"
        case .grammar(let pattern, _):
            if let patternId = pattern.patternId, !patternId.isEmpty {
                id += "#grammar-\(patternId)"
            } else if let pointID = pattern.grammarPointID, !pointID.isEmpty {
                id += "#grammar-\(pointID)"
            } else {
                id += "#grammar"
            }
        }
        return id
    }

    private static func trimmedExportText(_ text: String, maxLength: Int = 240) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]) + "…"
    }
}
