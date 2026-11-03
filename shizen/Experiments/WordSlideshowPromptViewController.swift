//
//  WordSlideshowPromptViewController.swift
//  shizen
//
//  Entry for prompt-generated word slideshows: a request ("the days of the
//  week", "5 opposites"), a layout, and editable model instructions. Generates
//  on device with Apple Intelligence, then opens the review screen.
//

import UIKit

final class WordSlideshowPromptViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let requestField = UITextField()
    private let layoutControl = UISegmentedControl(items: WordSlideshowLayout.allCases.map(\.title))
    private let layoutHint = UILabel()
    private let examplesSwitch = UISwitch()
    private let instructionsView = UITextView()
    private let statusLabel = UILabel()
    private let generateButton = UIButton(type: .system)
    private let samplesButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var generateTask: Task<Void, Never>?

    private var selectedLayout: WordSlideshowLayout {
        let index = layoutControl.selectedSegmentIndex
        return WordSlideshowLayout.allCases.indices.contains(index) ? WordSlideshowLayout.allCases[index] : .single
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Word slideshows"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset prompt",
            style: .plain,
            target: self,
            action: #selector(resetInstructionsTapped)
        )

        installLayout()
        loadStoredValues()
        updateGenerateEnabled()
        updateAvailabilityStatus()
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

        requestField.borderStyle = .roundedRect
        requestField.placeholder = WordSlideshowPromptStore.defaultRequest
        requestField.autocapitalizationType = .sentences
        requestField.clearButtonMode = .whileEditing
        requestField.returnKeyType = .done
        requestField.delegate = self
        requestField.font = .preferredFont(forTextStyle: .body)
        requestField.addAction(UIAction { [weak self] _ in
            self?.updateGenerateEnabled()
        }, for: .editingChanged)

        let requestHint = UILabel()
        requestHint.text = "What to teach, e.g. \"the days of the week\", \"5 opposites\", \"colors\"."
        requestHint.font = .preferredFont(forTextStyle: .footnote)
        requestHint.textColor = .secondaryLabel
        requestHint.numberOfLines = 0

        layoutControl.addAction(UIAction { [weak self] _ in
            self?.updateLayoutHint()
        }, for: .valueChanged)

        layoutHint.font = .preferredFont(forTextStyle: .footnote)
        layoutHint.textColor = .secondaryLabel
        layoutHint.numberOfLines = 0

        let examplesLabel = UILabel()
        examplesLabel.text = "Include examples"
        examplesLabel.font = .preferredFont(forTextStyle: .body)
        let examplesRow = UIStackView(arrangedSubviews: [examplesLabel, examplesSwitch])
        examplesRow.axis = .horizontal
        examplesRow.alignment = .center
        examplesRow.spacing = 12

        let examplesHint = UILabel()
        examplesHint.text = "Adds a short example sentence for each word, in Japanese with furigana and in English, with the word highlighted. Takes a few extra seconds per word."
        examplesHint.font = .preferredFont(forTextStyle: .footnote)
        examplesHint.textColor = .secondaryLabel
        examplesHint.numberOfLines = 0

        let instructionsHint = UILabel()
        instructionsHint.text = "Instructions the on-device model follows for every request. The model only picks words and meanings; the app checks them against the dictionary."
        instructionsHint.font = .preferredFont(forTextStyle: .footnote)
        instructionsHint.textColor = .secondaryLabel
        instructionsHint.numberOfLines = 0

        instructionsView.font = .preferredFont(forTextStyle: .body)
        instructionsView.backgroundColor = ExperimentPalette.cardSurface
        instructionsView.layer.cornerRadius = 10
        instructionsView.layer.cornerCurve = .continuous
        instructionsView.layer.borderWidth = ExperimentCardStroke.normalWidth
        instructionsView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        instructionsView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        instructionsView.isScrollEnabled = false
        instructionsView.delegate = self
        instructionsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        var generateConfig = UIButton.Configuration.filled()
        generateConfig.title = "Generate"
        generateConfig.image = UIImage(systemName: "apple.intelligence")
        generateConfig.imagePadding = 8
        generateButton.configuration = generateConfig
        generateButton.addAction(UIAction { [weak self] _ in
            self?.generateTapped()
        }, for: .touchUpInside)

        var samplesConfig = UIButton.Configuration.bordered()
        samplesConfig.title = "Samples"
        samplesButton.configuration = samplesConfig
        samplesButton.showsMenuAsPrimaryAction = true
        samplesButton.menu = UIMenu(children: [
            UIAction(title: "Days of the week", subtitle: "1 per slide") { [weak self] _ in
                self?.openReview(WordSlideshowSamples.daysOfTheWeek(layout: .single))
            },
            UIAction(title: "Days of the week", subtitle: "2 per slide") { [weak self] _ in
                self?.openReview(WordSlideshowSamples.daysOfTheWeek(layout: .double))
            },
            UIAction(title: "Japanese opposites", subtitle: "Pairs") { [weak self] _ in
                self?.openReview(WordSlideshowSamples.opposites())
            },
            UIAction(title: "Days of the week", subtitle: "1 per slide · examples") { [weak self] _ in
                self?.openReview(WordSlideshowSamples.daysOfTheWeek(layout: .single, withExamples: true))
            },
            UIAction(title: "Japanese opposites", subtitle: "Pairs · examples") { [weak self] _ in
                self?.openReview(WordSlideshowSamples.opposites(withExamples: true))
            },
        ])

        activityIndicator.hidesWhenStopped = true

        let buttonRow = UIStackView(arrangedSubviews: [generateButton, samplesButton, activityIndicator])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .center

        [
            sectionHeader("Request"),
            requestField,
            requestHint,
            sectionHeader("Layout"),
            layoutControl,
            layoutHint,
            examplesRow,
            examplesHint,
            sectionHeader("Model instructions"),
            instructionsHint,
            instructionsView,
            statusLabel,
            buttonRow,
        ].forEach { contentStack.addArrangedSubview($0) }

        contentStack.setCustomSpacing(20, after: requestHint)
        contentStack.setCustomSpacing(16, after: layoutHint)
        contentStack.setCustomSpacing(20, after: examplesHint)
        contentStack.setCustomSpacing(20, after: instructionsView)
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
        requestField.text = WordSlideshowPromptStore.lastRequest
        instructionsView.text = WordSlideshowPromptStore.instructions
        layoutControl.selectedSegmentIndex = WordSlideshowLayout.allCases.firstIndex(of: WordSlideshowPromptStore.lastLayout) ?? 0
        examplesSwitch.isOn = WordSlideshowPromptStore.includeExamples
        updateLayoutHint()
    }

    private func updateLayoutHint() {
        layoutHint.text = selectedLayout.subtitle
    }

    private func updateAvailabilityStatus() {
        if WordSlideshowGenerator.isAvailable {
            statusLabel.text = "Runs on device with Apple Intelligence. You can review and edit the words before making slides."
            statusLabel.textColor = .secondaryLabel
        } else {
            statusLabel.text = "\(WordSlideshowGenerator.unavailabilityMessage) Samples still open."
            statusLabel.textColor = .systemRed
        }
    }

    private func updateGenerateEnabled() {
        let hasRequest = !(requestField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasInstructions = !instructionsView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        generateButton.isEnabled = hasRequest && hasInstructions && generateTask == nil && WordSlideshowGenerator.isAvailable
    }

    @objc private func resetInstructionsTapped() {
        WordSlideshowPromptStore.resetInstructionsToDefault()
        instructionsView.text = WordSlideshowPromptStore.defaultInstructions
        statusLabel.text = "Instructions reset to default."
        statusLabel.textColor = .secondaryLabel
        updateGenerateEnabled()
    }

    private func openReview(_ deck: WordSlideshowDeck, request: String? = nil) {
        navigationController?.pushViewController(
            WordSlideshowReviewViewController(deck: deck, request: request),
            animated: true
        )
    }

    private func generateTapped() {
        view.endEditing(true)

        let request = requestField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let instructions = instructionsView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !instructions.isEmpty else { return }
        let layout = selectedLayout
        let includeExamples = examplesSwitch.isOn

        WordSlideshowPromptStore.lastRequest = request
        WordSlideshowPromptStore.instructions = instructions
        WordSlideshowPromptStore.lastLayout = layout
        WordSlideshowPromptStore.includeExamples = includeExamples

        generateTask?.cancel()
        activityIndicator.startAnimating()
        generateButton.isEnabled = false
        statusLabel.text = "Generating…"
        statusLabel.textColor = .secondaryLabel

        generateTask = Task { [weak self] in
            do {
                let deck = try await WordSlideshowGenerator.generate(
                    request: request,
                    layout: layout,
                    includeExamples: includeExamples,
                    instructions: instructions
                ) { [weak self] done, total in
                    self?.statusLabel.text = "Writing examples \(min(done + 1, total)) of \(total)…"
                }
                guard !Task.isCancelled, let self else { return }
                self.finishGenerating()
                self.openReview(deck, request: request)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.finishGenerating()
                self.statusLabel.text = error.localizedDescription
                self.statusLabel.textColor = .systemRed
            }
        }
    }

    private func finishGenerating() {
        generateTask = nil
        activityIndicator.stopAnimating()
        updateGenerateEnabled()
        if statusLabel.textColor != .systemRed {
            updateAvailabilityStatus()
        }
    }
}

extension WordSlideshowPromptViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension WordSlideshowPromptViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateGenerateEnabled()
    }
}
