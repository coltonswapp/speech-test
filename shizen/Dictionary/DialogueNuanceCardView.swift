//
//  DialogueNuanceCardView.swift
//  shizen
//
//  Rounded card for a dialogue line’s deeper meaning.
//

import InteractionKit
import UIKit

final class DialogueNuanceCardView: UIView {

    enum State {
        case loading
        case result(GeminiDialogueNuance.Result, feedback: LLMFeedbackReceipt?)
        case unavailable(String)
        case failed(String)
    }

    private let surface = UIView()
    private let sectionStack = UIStackView()
    private let sectionTitle = UILabel()
    private let loadingRow = UIStackView()
    private let loadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let loadingLabel = UILabel()
    private let headlineLabel = UILabel()
    private let noteLabel = UILabel()
    private let feedbackRow = LLMFeedbackRow()
    private let messageLabel = UILabel()

    private static let contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let shadowBleed: CGFloat = 12
    private static let accentColor = UIColor.systemYellow
    private static let edgeControlLift: CGFloat = 8
    private static let thumbsOverlap: CGFloat = 18

    private var sectionBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func apply(_ state: State) {
        switch state {
        case .loading:
            loadingRow.isHidden = false
            loadingSpinner.isHidden = false
            loadingSpinner.reset()
            headlineLabel.isHidden = true
            noteLabel.isHidden = true
            feedbackRow.dismiss()
            messageLabel.isHidden = true
            headlineLabel.text = nil
            noteLabel.text = nil
            messageLabel.text = nil
        case .result(let result, let feedback):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            messageLabel.isHidden = true
            messageLabel.text = nil

            let headline = result.impliedMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            headlineLabel.text = headline.isEmpty ? nil : headline
            headlineLabel.isHidden = headline.isEmpty

            let note = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            noteLabel.text = note.isEmpty ? nil : note
            noteLabel.isHidden = note.isEmpty
            feedbackRow.present(feedback)
        case .unavailable(let message), .failed(let message):
            loadingRow.isHidden = true
            loadingSpinner.isHidden = true
            headlineLabel.isHidden = true
            noteLabel.isHidden = true
            feedbackRow.dismiss()
            headlineLabel.text = nil
            noteLabel.text = nil
            messageLabel.text = message
            messageLabel.isHidden = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        updateEdgeChrome()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.layer.shadowPath = UIBezierPath(
            roundedRect: surface.bounds,
            cornerRadius: surface.layer.cornerRadius
        ).cgPath
    }

    private func setupUI() {
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        sectionTitle.text = "DEEPER MEANING"
        sectionTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        sectionTitle.textColor = .secondaryLabel

        let headlineFont: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .title3)
            if let d = base.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: d, size: 0)
            }
            return base
        }()
        headlineLabel.font = headlineFont
        headlineLabel.textColor = .label
        headlineLabel.textAlignment = .natural
        headlineLabel.numberOfLines = 0

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .secondaryLabel
        noteLabel.textAlignment = .natural
        noteLabel.numberOfLines = 0
        noteLabel.isHidden = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .natural
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true

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
        sectionStack.addArrangedSubview(sectionTitle)
        sectionStack.addArrangedSubview(loadingRow)
        sectionStack.addArrangedSubview(headlineLabel)
        sectionStack.addArrangedSubview(noteLabel)
        sectionStack.addArrangedSubview(messageLabel)
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

        apply(.loading)
    }

    private func updateEdgeChrome() {
        let showingThumbs = !feedbackRow.isHidden
        let overlap = showingThumbs ? Self.thumbsOverlap + Self.edgeControlLift : 0
        sectionBottomConstraint?.constant = -(Self.contentInsets.bottom + overlap)
        bringSubviewToFront(feedbackRow)
    }
}
