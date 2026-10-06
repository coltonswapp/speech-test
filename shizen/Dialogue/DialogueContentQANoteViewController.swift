//
//  DialogueContentQANoteViewController.swift
//  shizen
//
//  Shohei QA note composer: growing note field, hashtag chips, Studio client POST.
//

import UIKit

/// Routing hints Shohei's agents read from the note text.
enum ContentQANoteTag: String, CaseIterable {
    case content
    case bug
    case localPrompt = "local-prompt"
    case remoteAgent = "remote-agent"
    case ux
    case quiz
    case fyi
    case question

    var hashtag: String { "#\(rawValue)" }
}

final class DialogueContentQANoteViewController: UIViewController, UITextViewDelegate {

    private let source: ContentCMSClient.QANoteSource
    private let sourceId: String
    private let focusTitle: String
    private let focusDetailLines: [String]
    private let lessonTitle: String
    private let lessonID: String
    private let sceneTitle: String?
    private let sceneSlug: String?
    private let studioLink: String

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let noteTextView = UITextView()
    private let sendButton = PrimaryButton(type: .system)
    private let contextDisclosureButton = UIButton(type: .system)
    private let contextChevron = UIImageView()
    private let contextBodyLabel = UILabel()
    private var tagButtons: [(tag: ContentQANoteTag, button: GlassTagControl)] = []
    private var keyboardObservers: [NSObjectProtocol] = []
    private var isSending = false
    private var contextExpanded = false

    init(
        source: ContentCMSClient.QANoteSource,
        sourceId: String,
        focusTitle: String,
        focusDetailLines: [String],
        lessonTitle: String,
        lessonID: String,
        sceneTitle: String? = nil,
        sceneSlug: String? = nil,
        studioLink: String
    ) {
        self.source = source
        self.sourceId = sourceId
        self.focusTitle = focusTitle
        self.focusDetailLines = focusDetailLines
        self.lessonTitle = lessonTitle
        self.lessonID = lessonID
        self.sceneTitle = sceneTitle
        self.sceneSlug = sceneSlug
        self.studioLink = studioLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.title = focusTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        let copyItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyTapped)
        )
        copyItem.accessibilityLabel = "Copy for agent"
        navigationItem.leftBarButtonItem = copyItem

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        stack.addArrangedSubview(makeMetaBlock())
        stack.addArrangedSubview(makeNoteSection())

        sendButton.primaryStyle = .yellow
        sendButton.setTitle("Send to agent", for: .normal)
        sendButton.accessibilityLabel = "Send to agent"
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        view.addSubview(sendButton)

        NSLayoutConstraint.activate([
            sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            sendButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            sendButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -32),
        ])

        installKeyboardScrollObservers()
    }

    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollCaretIntoView(animated: true)
    }

    private func installKeyboardScrollObservers() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.keyboardWillChangeFrame(notification)
            },
        ]
    }

    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
            self.scrollCaretIntoView(animated: false)
        }
    }

    /// The text view grows instead of scrolling, so the outer scroll view follows the caret.
    private func scrollCaretIntoView(animated: Bool) {
        guard noteTextView.isFirstResponder, let selection = noteTextView.selectedTextRange else { return }
        view.layoutIfNeeded()
        let caret = noteTextView.caretRect(for: selection.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        let target = noteTextView.convert(caret, to: scrollView)
        scrollView.scrollRectToVisible(target.insetBy(dx: 0, dy: -24), animated: animated)
    }

    func textViewDidChange(_ textView: UITextView) {
        scrollCaretIntoView(animated: false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        scrollCaretIntoView(animated: false)
    }

    private func makeMetaBlock() -> UIView {
        contextChevron.image = UIImage(systemName: "chevron.right")
        contextChevron.tintColor = .secondaryLabel
        contextChevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .subheadline,
            scale: .small
        )
        contextChevron.setContentHuggingPriority(.required, for: .horizontal)
        contextChevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let title = UILabel()
        title.text = "Context"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [contextChevron, title])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        contextDisclosureButton.accessibilityLabel = "Context"
        contextDisclosureButton.accessibilityValue = "Collapsed"
        contextDisclosureButton.addTarget(self, action: #selector(toggleContextExpanded), for: .touchUpInside)
        contextDisclosureButton.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contextDisclosureButton.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: contextDisclosureButton.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: contextDisclosureButton.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: contextDisclosureButton.trailingAnchor),
        ])

        contextBodyLabel.numberOfLines = 0
        contextBodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextBodyLabel.textColor = .secondaryLabel
        contextBodyLabel.text = contextLines().joined(separator: "\n")
        contextBodyLabel.isHidden = true

        let wrap = UIStackView(arrangedSubviews: [contextDisclosureButton, contextBodyLabel])
        wrap.axis = .vertical
        wrap.spacing = 8
        wrap.alignment = .fill
        return wrap
    }

    @objc private func toggleContextExpanded() {
        contextExpanded.toggle()
        contextChevron.image = UIImage(systemName: contextExpanded ? "chevron.down" : "chevron.right")
        contextDisclosureButton.accessibilityValue = contextExpanded ? "Expanded" : "Collapsed"
        UIView.animate(withDuration: 0.2) {
            self.contextBodyLabel.isHidden = !self.contextExpanded
            self.view.layoutIfNeeded()
        }
    }

    private func makeNoteSection() -> UIView {
        let heading = UILabel()
        heading.text = "Note"
        heading.font = .preferredFont(forTextStyle: .headline)

        noteTextView.font = .preferredFont(forTextStyle: .body)
        noteTextView.layer.cornerRadius = 12
        noteTextView.layer.borderWidth = 1
        noteTextView.layer.borderColor = UIColor.separator.cgColor
        noteTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        noteTextView.isScrollEnabled = false
        noteTextView.delegate = self
        noteTextView.translatesAutoresizingMaskIntoConstraints = false
        noteTextView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        noteTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let wrap = UIStackView(arrangedSubviews: [heading, noteTextView, makeTagFlow()])
        wrap.axis = .vertical
        wrap.spacing = 8
        wrap.setCustomSpacing(14, after: noteTextView)
        return wrap
    }

    private func makeTagFlow() -> UIView {
        tagButtons = ContentQANoteTag.allCases.map { tag in
            (tag, GlassTagControl(title: tag.hashtag))
        }
        let flow = GlassTagFlowView()
        flow.setTags(tagButtons.map(\.button))
        flow.setContentCompressionResistancePriority(.required, for: .vertical)
        return flow
    }

    private var typedNote: String {
        noteTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTags: [ContentQANoteTag] {
        tagButtons.filter { $0.button.isSelected }.map(\.tag)
    }

    private func tagLines() -> [String] {
        let tags = selectedTags
        guard !tags.isEmpty else { return [] }
        return ["Tags: " + tags.map(\.hashtag).joined(separator: " "), ""]
    }

    private func contextLines() -> [String] {
        var lines = [
            "Looking at: \(focusTitle)",
        ]
        lines.append(contentsOf: focusDetailLines)
        lines.append("")
        lines.append("Lesson: \(lessonTitle) (\(lessonID))")
        if let sceneTitle, let sceneSlug {
            lines.append("Scene: \(sceneTitle) (\(sceneSlug))")
        }
        lines.append("Studio: \(studioLink)")
        return lines
    }

    static func present(
        from presenter: UIViewController,
        source: ContentCMSClient.QANoteSource,
        sourceId: String,
        focusTitle: String,
        focusDetailLines: [String],
        lessonTitle: String,
        lessonID: String,
        sceneTitle: String? = nil,
        sceneSlug: String? = nil,
        studioLink: String
    ) {
        let note = DialogueContentQANoteViewController(
            source: source,
            sourceId: sourceId,
            focusTitle: focusTitle,
            focusDetailLines: focusDetailLines,
            lessonTitle: lessonTitle,
            lessonID: lessonID,
            sceneTitle: sceneTitle,
            sceneSlug: sceneSlug,
            studioLink: studioLink
        )
        let sheet = UINavigationController(rootViewController: note)
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .large
            presentation.prefersGrabberVisible = true
        }
        presenter.present(sheet, animated: true)
    }

    private func agentPasteboardText() -> String {
        var lines = tagLines() + contextLines()
        lines.append("")
        lines.append("Note:")
        lines.append(typedNote)
        return lines.joined(separator: "\n")
    }

    private func webhookNoteText() -> String {
        (tagLines() + [typedNote, ""] + contextLines()).joined(separator: "\n")
    }

    @objc private func copyTapped() {
        view.endEditing(true)
        UIPasteboard.general.string = agentPasteboardText()
        showToast(text: "Copied")
    }

    @objc private func sendTapped() {
        guard !isSending else { return }
        guard !typedNote.isEmpty else {
            showToast(text: "Write a note first", sentiment: .negative)
            return
        }
        view.endEditing(true)
        setSending(true)
        let note = ContentCMSClient.QANote(
            source: source,
            sourceId: sourceId,
            title: focusTitle,
            note: webhookNoteText(),
            metadata: .init(
                url: studioLink,
                createdAt: Date(),
                screenshotJPEG: lessonHostView().flatMap(LessonHostSnapshot.jpegBase64(of:))
            )
        )
        ContentCMSClient.sendQANote(note) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setSending(false)
                switch result {
                case .success:
                    self.showToast(text: "Sent to Shohei")
                    self.dismiss(animated: true)
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Couldn’t send note",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        sendButton.isEnabled = !sending
        sendButton.setTitle(sending ? "Sending…" : "Send to agent", for: .normal)
        isModalInPresentation = sending
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    /// The lesson, quiz, or other surface that presented this sheet. Not the sheet itself.
    private func lessonHostView() -> UIView? {
        guard let host = presentingViewController?.view else { return nil }
        if let sheetView = navigationController?.view,
           host === sheetView || host.isDescendant(of: sheetView) {
            return nil
        }
        return host
    }
}

/// Downscaled JPEG of a UIKit view. Long edge is about 1200px so the note webhook stays small.
private enum LessonHostSnapshot {
    static let maxLongEdge: CGFloat = 1200
    static let jpegQuality: CGFloat = 0.6
    /// Keep in sync with `SCREENSHOT_JPEG_MAX_CHARS` in the note schema.
    static let maxBase64Characters = 1_500_000

    static func jpegBase64(of view: UIView) -> String? {
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        let scale = view.traitCollection.displayScale > 0 ? view.traitCollection.displayScale : 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            (view.backgroundColor ?? .white).setFill()
            context.fill(bounds)
            view.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        guard let data = scaledDown(image, maxLongEdge: maxLongEdge).jpegData(compressionQuality: jpegQuality),
              !data.isEmpty else {
            return nil
        }
        let encoded = data.base64EncodedString()
        guard encoded.count <= maxBase64Characters else { return nil }
        return encoded
    }

    private static func scaledDown(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }
        let ratio = maxLongEdge / longEdge
        let target = CGSize(
            width: max(floor(pixelWidth * ratio), 1),
            height: max(floor(pixelHeight * ratio), 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
