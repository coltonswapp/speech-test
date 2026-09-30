//
//  VerbComboPromptViewController.swift
//  shizen
//
//  Entry for verb-combination slideshows: an editable Gemini prompt that
//  returns pattern decks, plus the みる sample (hook, rule, three examples).
//

import UIKit

final class VerbComboPromptViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let themeField = UITextField()
    private let promptView = UITextView()
    private let statusLabel = UILabel()
    private let generateButton = UIButton(type: .system)
    private let samplesButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var generateTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Verb combinations"
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

        themeField.borderStyle = .roundedRect
        themeField.placeholder = VerbComboPromptStore.defaultTheme
        themeField.autocapitalizationType = .sentences
        themeField.clearButtonMode = .whileEditing
        themeField.returnKeyType = .done
        themeField.delegate = self
        themeField.font = .preferredFont(forTextStyle: .body)
        themeField.addAction(UIAction { [weak self] _ in
            self?.updateGenerateEnabled()
        }, for: .editingChanged)

        let promptHint = UILabel()
        promptHint.text = "Include \(VerbComboPromptStore.themePlaceholder) where the theme should be inserted. Each slideshow is 5 stills: hook, rule, then 3 examples."
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
        promptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

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

        var samplesConfig = UIButton.Configuration.bordered()
        samplesConfig.title = "Open sample"
        samplesButton.configuration = samplesConfig
        samplesButton.addAction(UIAction { [weak self] _ in
            self?.openSamples()
        }, for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true

        let buttonRow = UIStackView(arrangedSubviews: [generateButton, samplesButton, activityIndicator])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .center

        [
            sectionHeader("Theme"),
            themeField,
            sectionHeader("Usage prompt"),
            promptHint,
            promptView,
            statusLabel,
            buttonRow,
        ].forEach { contentStack.addArrangedSubview($0) }

        contentStack.setCustomSpacing(20, after: themeField)
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
        themeField.text = VerbComboPromptStore.lastTheme
        promptView.text = VerbComboPromptStore.usagePrompt
    }

    private func updateKeyStatus() {
        if VerbComboGenerator.isConfigured {
            if statusLabel.textColor != .systemRed {
                statusLabel.text = "Uses Gemini (\(VerbComboGenerator.Model.flash.rawValue)). Each result is 5 exportable stills."
                statusLabel.textColor = .secondaryLabel
            }
        } else {
            statusLabel.text = "Gemini API key missing — add GEMINI_API_KEY to Secrets.plist or the environment. The sample still opens."
            statusLabel.textColor = .systemRed
        }
    }

    private func updateGenerateEnabled() {
        let hasTheme = !(themeField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPrompt = !promptView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPlaceholder = promptView.text.contains(VerbComboPromptStore.themePlaceholder)
        generateButton.isEnabled = hasTheme && hasPrompt && hasPlaceholder && generateTask == nil && VerbComboGenerator.isConfigured
    }

    @objc private func resetPromptTapped() {
        VerbComboPromptStore.resetPromptToDefault()
        promptView.text = VerbComboPromptStore.defaultPrompt
        statusLabel.text = "Prompt reset to default."
        statusLabel.textColor = .secondaryLabel
        updateGenerateEnabled()
    }

    private func openSamples() {
        navigationController?.pushViewController(
            VerbComboPagerViewController(deck: VerbComboSamples.miru),
            animated: true
        )
    }

    private func generateTapped() {
        view.endEditing(true)

        let theme = themeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prompt = promptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !theme.isEmpty, !prompt.isEmpty else { return }

        VerbComboPromptStore.lastTheme = theme
        VerbComboPromptStore.usagePrompt = prompt

        generateTask?.cancel()
        activityIndicator.startAnimating()
        generateButton.isEnabled = false
        statusLabel.text = "Generating slideshows…"
        statusLabel.textColor = .secondaryLabel

        generateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let decks = try await VerbComboGenerator.generate(theme: theme, usagePrompt: prompt)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.finishGenerating()
                    let page: UIViewController = decks.count == 1
                        ? VerbComboPagerViewController(deck: decks[0])
                        : VerbComboListViewController(decks: decks)
                    self.navigationController?.pushViewController(page, animated: true)
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

extension VerbComboPromptViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension VerbComboPromptViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateGenerateEnabled()
    }
}
