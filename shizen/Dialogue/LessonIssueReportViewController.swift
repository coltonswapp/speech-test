//
//  LessonIssueReportViewController.swift
//  shizen
//
//  "Report a problem" sheet: category chips, an optional note, and a collapsed
//  preview of the context that goes with the report.
//

import UIKit

final class LessonIssueReportViewController: UIViewController, UITextViewDelegate,
    UIAdaptivePresentationControllerDelegate {

    private let context: LessonIssueContext

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let noteTextView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = PrimaryButton(type: .system)
    private let contextDisclosureButton = UIButton(type: .system)
    private let contextChevron = UIImageView()
    private let contextBodyLabel = UILabel()
    private var categoryTags: [(category: LessonIssueCategory, control: GlassTagControl)] = []
    private var isSending = false
    private var contextExpanded = false

    init(context: LessonIssueContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func present(from presenter: UIViewController, context: LessonIssueContext) {
        let report = LessonIssueReportViewController(context: context)
        let sheet = UINavigationController(rootViewController: report)
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .large
            presentation.prefersGrabberVisible = true
        }
        sheet.presentationController?.delegate = report
        presenter.present(sheet, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.title = "Report a problem"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makeCategorySection())
        stack.addArrangedSubview(makeNoteSection())
        stack.addArrangedSubview(makeContextBlock())

        sendButton.primaryStyle = .yellow
        sendButton.setTitle("Send", for: .normal)
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
        ])

        updateSendState()
    }

    // MARK: - Sections

    private func makeHeader() -> UIView {
        let title = UILabel()
        title.text = "What went wrong?"
        title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.text = "About: \(context.focusTitle)"
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let wrap = UIStackView(arrangedSubviews: [title, subtitle])
        wrap.axis = .vertical
        wrap.spacing = 4
        return wrap
    }

    private func makeCategorySection() -> UIView {
        categoryTags = LessonIssueCategory.allCases.map { category in
            let control = GlassTagControl(title: category.title)
            control.addAction(UIAction { [weak self] _ in
                self?.updateSendState()
            }, for: .valueChanged)
            return (category, control)
        }
        let flow = GlassTagFlowView()
        flow.setTags(categoryTags.map(\.control))
        flow.setContentCompressionResistancePriority(.required, for: .vertical)
        return flow
    }

    private func makeNoteSection() -> UIView {
        noteTextView.font = .preferredFont(forTextStyle: .body)
        noteTextView.adjustsFontForContentSizeCategory = true
        noteTextView.backgroundColor = .secondarySystemBackground
        noteTextView.layer.cornerRadius = 12
        noteTextView.layer.cornerCurve = .continuous
        noteTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        noteTextView.isScrollEnabled = false
        noteTextView.delegate = self
        noteTextView.accessibilityLabel = "Details"
        noteTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        placeholderLabel.text = "Tell us more (optional)"
        placeholderLabel.font = noteTextView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        noteTextView.addSubview(placeholderLabel)
        let inset = noteTextView.textContainerInset
        let padding = noteTextView.textContainer.lineFragmentPadding
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: noteTextView.topAnchor, constant: inset.top),
            placeholderLabel.leadingAnchor.constraint(equalTo: noteTextView.leadingAnchor, constant: inset.left + padding),
        ])
        return noteTextView
    }

    private func makeContextBlock() -> UIView {
        contextChevron.image = UIImage(systemName: "chevron.right")
        contextChevron.tintColor = .secondaryLabel
        contextChevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .subheadline,
            scale: .small
        )
        contextChevron.setContentHuggingPriority(.required, for: .horizontal)

        let title = UILabel()
        title.text = "Included with your report"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [contextChevron, title])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        contextDisclosureButton.accessibilityLabel = "Included with your report"
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
        contextBodyLabel.font = .preferredFont(forTextStyle: .footnote)
        contextBodyLabel.textColor = .secondaryLabel
        contextBodyLabel.text = contextLines().joined(separator: "\n")
        contextBodyLabel.isHidden = true

        let wrap = UIStackView(arrangedSubviews: [contextDisclosureButton, contextBodyLabel])
        wrap.axis = .vertical
        wrap.spacing = 8
        wrap.alignment = .fill
        return wrap
    }

    private func contextLines() -> [String] {
        var lines = [context.focusTitle]
        lines.append(contentsOf: context.focusDetails)
        lines.append("Scene: \(context.collectionId)/\(context.scenarioId)")
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            lines.append("App version: \(version)")
        }
        return lines
    }

    // MARK: - State

    private var typedNote: String {
        noteTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCategories: [LessonIssueCategory] {
        categoryTags.filter { $0.control.isSelected }.map(\.category)
    }

    private var hasDraft: Bool {
        !typedNote.isEmpty || !selectedCategories.isEmpty
    }

    private func updateSendState() {
        sendButton.isEnabled = hasDraft && !isSending
        isModalInPresentation = hasDraft || isSending
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendState()
        if let selection = textView.selectedTextRange {
            let caret = textView.convert(textView.caretRect(for: selection.end), to: scrollView)
            scrollView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -24), animated: false)
        }
    }

    // MARK: - Actions

    @objc private func toggleContextExpanded() {
        contextExpanded.toggle()
        contextChevron.image = UIImage(systemName: contextExpanded ? "chevron.down" : "chevron.right")
        contextDisclosureButton.accessibilityValue = contextExpanded ? "Expanded" : "Collapsed"
        UIView.animate(withDuration: 0.2) {
            self.contextBodyLabel.isHidden = !self.contextExpanded
            self.view.layoutIfNeeded()
        }
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        guard !isSending else { return }
        cancelTapped()
    }

    @objc private func cancelTapped() {
        guard hasDraft else {
            dismiss(animated: true)
            return
        }
        let confirm = UIAlertController(title: "Discard this report?", message: nil, preferredStyle: .actionSheet)
        confirm.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        confirm.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
        confirm.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(confirm, animated: true)
    }

    @objc private func sendTapped() {
        guard !isSending, hasDraft else { return }
        view.endEditing(true)
        setSending(true)
        let context = context
        let categories = selectedCategories
        let note = typedNote
        Task { [weak self] in
            do {
                try await LLMGatewayClient.postLessonReport(context, categories: categories, note: note)
                await MainActor.run {
                    guard let self else { return }
                    self.setSending(false)
                    let presenter = self.presentingViewController
                    self.dismiss(animated: true) {
                        presenter?.showToast(text: "Thanks — we'll take a look")
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.setSending(false)
                    self.presentSendFailure(error)
                }
            }
        }
    }

    private func presentSendFailure(_ error: Error) {
        let message: String
        if case LLMGatewayError.httpStatus(429) = error {
            message = "You've sent a lot of reports recently. Try again in a little while."
        } else {
            message = error.localizedDescription
        }
        let alert = UIAlertController(title: "Couldn't send report", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        sendButton.setTitle(sending ? "Sending…" : "Send", for: .normal)
        updateSendState()
    }
}
