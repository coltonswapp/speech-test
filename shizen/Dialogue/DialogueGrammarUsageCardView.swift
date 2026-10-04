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
    private let feedbackRow = LLMFeedbackRow()

    private static let contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let shadowBleed: CGFloat = 12
    private static let accentColor = UIColor.systemYellow
    private static let edgeControlLift: CGFloat = 8
    private static let thumbsOverlap: CGFloat = 18

    private var sectionBottomConstraint: NSLayoutConstraint?
    /// Offered thumbs whose space is already reserved but which appear only after the card settles.
    private var pendingFeedback: LLMFeedbackReceipt?

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

    func presentPendingFeedback() {
        guard let feedback = pendingFeedback else { return }
        pendingFeedback = nil
        feedbackRow.present(feedback)
        updateEdgeChrome()
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
            feedbackRow.dismiss()
        case .result(let result, let feedback):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            messageLabel.isHidden = true
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
        case .unavailable(let message), .failed(let message):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            resultLabels.forEach { $0.isHidden = true }
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

        for label in [formLabel, examplesLabel, noteLabel, messageLabel] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.isHidden = true
        }

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
        [sectionTitle, loadingRow, headlineLabel, formLabel, examplesLabel, noteLabel, messageLabel]
            .forEach { sectionStack.addArrangedSubview($0) }
        sectionStack.setCustomSpacing(8, after: formLabel)
        sectionStack.setCustomSpacing(8, after: examplesLabel)
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
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.shadowBleed),

            sectionStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: insets.top),
            sectionStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: insets.left),
            sectionStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -insets.right),
            sectionBottom,

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

    private func updateEdgeChrome() {
        let showingThumbs = !feedbackRow.isHidden || pendingFeedback != nil
        let overlap = showingThumbs ? Self.thumbsOverlap + Self.edgeControlLift : 0
        sectionBottomConstraint?.constant = -(Self.contentInsets.bottom + overlap)
        bringSubviewToFront(feedbackRow)
    }
}

extension UIFont {
    fileprivate func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
