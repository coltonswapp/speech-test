//
//  RegisterLadderPromptViewController.swift
//  shizen
//
//  Entry for the register-ladder experiment: tweakable Gemini usage prompt with
//  a [target sentence] placeholder, plus the English sentence to expand.
//

import UIKit

final class RegisterLadderPromptViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let targetField = UITextField()
    private let promptView = UITextView()
    private let statusLabel = UILabel()
    private let generateButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var generateTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Register ladder"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset prompt",
            style: .plain,
            target: self,
            action: #selector(resetPromptTapped)
        )

        installLayout()
        loadStoredValues()
        updateGenerateEnabled()
        updateKeyStatus()
    }

    deinit {
        generateTask?.cancel()
    }

    private func installLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let targetHeader = sectionHeader("Target sentence")
        targetField.borderStyle = .roundedRect
        targetField.placeholder = "Can I get the check?"
        targetField.autocapitalizationType = .sentences
        targetField.clearButtonMode = .whileEditing
        targetField.returnKeyType = .done
        targetField.delegate = self
        targetField.addAction(UIAction { [weak self] _ in
            self?.updateGenerateEnabled()
        }, for: .editingChanged)
        targetField.font = .preferredFont(forTextStyle: .body)

        let promptHeader = sectionHeader("Usage prompt")
        let promptHint = UILabel()
        promptHint.text = "Include \(RegisterLadderPromptStore.targetSentencePlaceholder) where the English sentence should be inserted."
        promptHint.font = .preferredFont(forTextStyle: .footnote)
        promptHint.textColor = .secondaryLabel
        promptHint.numberOfLines = 0

        promptView.font = .preferredFont(forTextStyle: .body)
        promptView.backgroundColor = ExperimentPalette.cardSurface
        promptView.layer.cornerRadius = 10
        promptView.layer.cornerCurve = .continuous
        promptView.layer.borderWidth = ExperimentCardStroke.normalWidth
        promptView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        promptView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        promptView.isScrollEnabled = false
        promptView.delegate = self
        promptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        var generateConfig = UIButton.Configuration.filled()
        generateConfig.title = "Generate"
        generateConfig.image = UIImage(systemName: "sparkles")
        generateConfig.imagePadding = 8
        generateButton.configuration = generateConfig
        generateButton.addAction(UIAction { [weak self] _ in
            self?.generateTapped()
        }, for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true

        let buttonRow = UIStackView(arrangedSubviews: [generateButton, activityIndicator])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .center

        [
            targetHeader,
            targetField,
            promptHeader,
            promptHint,
            promptView,
            statusLabel,
            buttonRow,
        ].forEach { contentStack.addArrangedSubview($0) }

        contentStack.setCustomSpacing(20, after: targetField)
        contentStack.setCustomSpacing(20, after: promptView)
        contentStack.setCustomSpacing(16, after: statusLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }

    private func loadStoredValues() {
        targetField.text = RegisterLadderPromptStore.lastTargetSentence
        promptView.text = RegisterLadderPromptStore.usagePrompt
    }

    private func updateKeyStatus() {
        if RegisterLadderGenerator.isConfigured {
            if statusLabel.textColor == .systemRed {
                // Keep error text until the next generate attempt.
            } else {
                statusLabel.text = "Uses on-device Gemini (\(RegisterLadderGenerator.Model.flash.rawValue))."
                statusLabel.textColor = .secondaryLabel
            }
        } else {
            statusLabel.text = "Gemini API key missing — add GEMINI_API_KEY to Secrets.plist or the environment."
            statusLabel.textColor = .systemRed
        }
    }

    private func updateGenerateEnabled() {
        let hasTarget = !(targetField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPrompt = !promptView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        generateButton.isEnabled = hasTarget && hasPrompt && generateTask == nil
    }

    @objc private func resetPromptTapped() {
        RegisterLadderPromptStore.resetPromptToDefault()
        promptView.text = RegisterLadderPromptStore.defaultPrompt
        statusLabel.text = "Prompt reset to default."
        statusLabel.textColor = .secondaryLabel
        updateGenerateEnabled()
    }

    private func generateTapped() {
        view.endEditing(true)

        let target = targetField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prompt = promptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !prompt.isEmpty else { return }

        RegisterLadderPromptStore.lastTargetSentence = target
        RegisterLadderPromptStore.usagePrompt = prompt

        generateTask?.cancel()
        activityIndicator.startAnimating()
        generateButton.isEnabled = false
        statusLabel.text = "Generating…"
        statusLabel.textColor = .secondaryLabel

        generateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let deck = try await RegisterLadderGenerator.generate(
                    targetSentence: target,
                    usagePrompt: prompt
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.finishGenerating()
                    self.navigationController?.pushViewController(
                        RegisterLadderPagerViewController(deck: deck),
                        animated: true
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.finishGenerating()
                    self.statusLabel.text = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    private func finishGenerating() {
        generateTask = nil
        activityIndicator.stopAnimating()
        updateGenerateEnabled()
        if statusLabel.textColor != .systemRed {
            updateKeyStatus()
        }
    }
}

extension RegisterLadderPromptViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension RegisterLadderPromptViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateGenerateEnabled()
    }
}
