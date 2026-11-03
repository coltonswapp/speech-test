//
//  RolePlayCompletionViewController.swift
//  shizen
//
//  Role Play wrap-up in the lesson completion style: aurora, headline, one
//  "worth a second look" card of the learner's lines, then the next rep.
//

import SwiftUI
import UIKit

final class RolePlayCompletionViewController: UIViewController {

    static let detentIdentifier = UISheetPresentationController.Detent.Identifier("rolePlayComplete")

    private static let contentTopInset: CGFloat = 22
    private static let contentSideInset: CGFloat = 20
    private static let actionsBottomInset: CGFloat = 16
    private static let secondaryActionHeight: CGFloat = 44

    var onPlayAs: ((String) -> Void)?
    var onSwitchRoles: (() -> Void)?
    var onReplay: (() -> Void)?
    var onClose: (() -> Void)?
    var onDismissed: (() -> Void)?
    var onToggleLinePlayback: ((Int) -> Void)?
    var onSelectPattern: ((DialogueGrammarPatternRef) -> Void)?
    /// DEBUG: recognizer usage / compare recap. Nil hides the link.
    var onShowRecognizerDetails: (() -> Void)?

    private let recap: RolePlayRecap

    private let auroraHost = UIHostingController(
        rootView: DialogueCompletionAuroraView(configuration: .production)
    )
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let linesCard: RolePlayLinesCardView
    private let primaryButton = PrimaryButton()
    private let actionsStack = UIStackView()
    private let replayButton = UIButton(type: .system)
    private let detailsButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var hasCommittedAction = false
    private var hasAnimatedIn = false

    init(recap: RolePlayRecap) {
        self.recap = recap
        self.linesCard = RolePlayLinesCardView(recap: recap)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        installContent()
        prepareEntranceAnimation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureSheetPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playEntranceAnimationIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDismissed?()
    }

    /// Mirrors the host's audio so the playing line's button shows pause.
    func setPlayingLine(_ index: Int?) {
        linesCard.setPlayingLine(index)
    }

    // MARK: - Layout

    private func installContent() {
        eyebrowLabel.text = "Role play complete".uppercased()
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = ExperimentPalette.meaningBadgeText
        eyebrowLabel.textAlignment = .center

        titleLabel.text = "You played \(recap.learnerSpeaker)"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = subtitleText
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        linesCard.onToggleLinePlayback = { [weak self] index in
            self?.onToggleLinePlayback?(index)
        }
        linesCard.onSelectPattern = { [weak self] pattern in
            self?.onSelectPattern?(pattern)
        }
        linesCard.isHidden = recap.lines.isEmpty

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        for subview in [eyebrowLabel, titleLabel, subtitleLabel, linesCard] {
            contentStack.addArrangedSubview(subview)
        }
        contentStack.setCustomSpacing(5, after: eyebrowLabel)
        contentStack.setCustomSpacing(8, after: titleLabel)
        contentStack.setCustomSpacing(22, after: subtitleLabel)

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        var closeConfiguration = UIButton.Configuration.gray()
        closeConfiguration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        closeConfiguration.cornerStyle = .capsule
        closeConfiguration.baseForegroundColor = .secondaryLabel
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.accessibilityLabel = "Close Role Play"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.commit { $0.onClose?() }
        }, for: .touchUpInside)

        auroraHost.view.backgroundColor = .clear
        auroraHost.view.isUserInteractionEnabled = false
        auroraHost.view.translatesAutoresizingMaskIntoConstraints = false

        // The other part is the natural next rep in a two-person scene.
        primaryButton.primaryStyle = .yellow
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        if let next = recap.nextSpeaker {
            primaryButton.setTitle("Play as \(next)", for: .normal)
            primaryButton.addAction(UIAction { [weak self] _ in
                self?.commit { $0.onPlayAs?(next) }
            }, for: .touchUpInside)
        } else {
            primaryButton.setTitle("Switch roles", for: .normal)
            primaryButton.addAction(UIAction { [weak self] _ in
                self?.commit { $0.onSwitchRoles?() }
            }, for: .touchUpInside)
        }

        replayButton.configuration = Self.secondaryActionConfiguration(
            title: "Replay as \(recap.learnerSpeaker)",
            systemImage: "arrow.counterclockwise"
        )
        replayButton.addAction(UIAction { [weak self] _ in
            self?.commit { $0.onReplay?() }
        }, for: .touchUpInside)

        actionsStack.axis = .vertical
        actionsStack.alignment = .fill
        actionsStack.spacing = 4
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.addArrangedSubview(primaryButton)
        actionsStack.setCustomSpacing(8, after: primaryButton)
        actionsStack.addArrangedSubview(replayButton)

        if onShowRecognizerDetails != nil {
            var details = UIButton.Configuration.plain()
            details.title = "Recognizer details"
            details.baseForegroundColor = .tertiaryLabel
            details.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 13, weight: .medium)
                return outgoing
            }
            detailsButton.configuration = details
            detailsButton.addAction(UIAction { [weak self] _ in
                self?.onShowRecognizerDetails?()
            }, for: .touchUpInside)
            actionsStack.addArrangedSubview(detailsButton)
        }

        addChild(auroraHost)
        view.addSubview(auroraHost.view)
        auroraHost.didMove(toParent: self)
        view.addSubview(scrollView)
        view.addSubview(closeButton)
        view.addSubview(actionsStack)

        let contentGuide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            auroraHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            auroraHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            auroraHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            auroraHost.view.heightAnchor.constraint(
                equalToConstant: DialogueAuroraConfiguration.production.height
            ),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionsStack.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: Self.contentTopInset),
            contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: Self.contentSideInset),
            contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -Self.contentSideInset),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -10),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -Self.contentSideInset * 2
            ),

            eyebrowLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -64),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24),
            subtitleLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),
            linesCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            primaryButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            replayButton.heightAnchor.constraint(equalToConstant: Self.secondaryActionHeight),
            actionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            actionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            actionsStack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.actionsBottomInset
            ),
        ])
    }

    private var subtitleText: String {
        let count = recap.spokenLineCount
        let lines = count == 1 ? "1 line" : "\(count) lines"
        return "\(lines) out loud · every rep builds fluency"
    }

    private static func secondaryActionConfiguration(title: String, systemImage: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.baseForegroundColor = .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        return config
    }

    private func commit(_ action: (RolePlayCompletionViewController) -> Void) {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        action(self)
    }

    // MARK: - Sheet sizing

    private var hostingSheet: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }

    private func configureSheetPresentation() {
        guard let sheet = hostingSheet else { return }
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.preferredCornerRadius = 28
        let detent = UISheetPresentationController.Detent.custom(
            identifier: Self.detentIdentifier
        ) { [weak self] context in
            guard let self else { return 560 }
            return min(self.fittedContentHeight, context.maximumDetentValue)
        }
        sheet.detents = [detent]
        sheet.selectedDetentIdentifier = Self.detentIdentifier
    }

    private var fittedContentHeight: CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let stackHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: max(width - Self.contentSideInset * 2, 0), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let actionsHeight = actionsStack.systemLayoutSizeFitting(
            CGSize(width: max(width - PrimaryButton.horizontalInset * 2, 0), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return view.safeAreaInsets.top
            + Self.contentTopInset
            + stackHeight
            + 10
            + 12
            + actionsHeight
            + Self.actionsBottomInset
            + view.safeAreaInsets.bottom
    }

    private func updatePreferredContentSize() {
        let height = fittedContentHeight
        guard abs(preferredContentSize.height - height) > 1 else { return }
        preferredContentSize = CGSize(width: view.bounds.width, height: height)
        hostingSheet?.invalidateDetents()
    }

    // MARK: - Entrance

    private func prepareEntranceAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        auroraHost.view.alpha = 0
        auroraHost.view.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        for label in [eyebrowLabel, titleLabel, subtitleLabel] {
            label.alpha = 0
            label.transform = CGAffineTransform(translationX: 0, y: 8)
        }
        linesCard.alpha = 0
        linesCard.transform = CGAffineTransform(translationX: 0, y: 18)
        actionsStack.alpha = 0
        actionsStack.transform = CGAffineTransform(translationX: 0, y: 12)
    }

    private func playEntranceAnimationIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        UIView.animate(
            withDuration: 0.55,
            delay: 0.05,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.auroraHost.view.alpha = 1
            self.auroraHost.view.transform = .identity
        }

        UIView.animate(withDuration: 0.35, delay: 0.12, options: [.curveEaseOut, .allowUserInteraction]) {
            for label in [self.eyebrowLabel, self.titleLabel, self.subtitleLabel] {
                label.alpha = 1
                label.transform = .identity
            }
        }

        UIView.animate(
            withDuration: 0.55,
            delay: 0.28,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.35,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.linesCard.alpha = 1
            self.linesCard.transform = .identity
        }
        linesCard.animateRowsIn(delay: 0.36)

        UIView.animate(
            withDuration: 0.45,
            delay: 0.46,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.25,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.actionsStack.alpha = 1
            self.actionsStack.transform = .identity
        }
    }
}

// MARK: - Lines card

/// Lesson-card treatment (`DialogueLessonScenesCardView`): caption, then one
/// row per line split by hairlines. Rows with grammar open the pattern detail.
private final class RolePlayLinesCardView: UIView {

    private static let inset: CGFloat = 18
    private static let playButtonSize: CGFloat = 34
    private static let playGlyphColor = UIColor.systemYellow
    private static var accentColor: UIColor { ExperimentPalette.meaningBadgeText }

    var onToggleLinePlayback: ((Int) -> Void)?
    var onSelectPattern: ((DialogueGrammarPatternRef) -> Void)?

    private let recap: RolePlayRecap
    private let contentStack = UIStackView()
    private var rows: [UIView] = []
    private var playButtons: [Int: UIButton] = [:]
    private var playingLineIndex: Int?

    init(recap: RolePlayRecap) {
        self.recap = recap
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }

    func setPlayingLine(_ index: Int?) {
        guard playingLineIndex != index else { return }
        playingLineIndex = index
        for (lineIndex, button) in playButtons {
            applyPlaySymbol(to: button, isPlaying: lineIndex == index)
        }
    }

    func animateRowsIn(delay: TimeInterval) {
        for (index, row) in rows.enumerated() {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 6)
            UIView.animate(
                withDuration: 0.35,
                delay: delay + TimeInterval(index) * 0.06,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerCurve = .continuous
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        let caption = UILabel()
        caption.text = recap.hasGrammar ? "WORTH A SECOND LOOK" : "YOUR LINES"
        caption.font = .systemFont(ofSize: 11, weight: .bold)
        caption.textColor = .secondaryLabel
        caption.accessibilityTraits = .header
        contentStack.addArrangedSubview(caption)

        for (index, line) in recap.lines.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                contentStack.addArrangedSubview(divider)
            }
            let row = makeRow(line)
            contentStack.addArrangedSubview(row)
            rows.append(row)
        }

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
        ])
    }

    private func makeRow(_ line: RolePlayRecap.Line) -> UIView {
        let row = UIView()

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        let japaneseLabel = UILabel()
        japaneseLabel.numberOfLines = 0
        japaneseLabel.attributedText = japaneseText(for: line)
        textStack.addArrangedSubview(japaneseLabel)

        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        if let pattern = line.patterns.first {
            detailLabel.attributedText = patternDetailText(pattern)
        } else {
            detailLabel.text = line.english
            detailLabel.font = .systemFont(ofSize: 13, weight: .medium)
            detailLabel.textColor = .secondaryLabel
        }
        detailLabel.isHidden = detailLabel.attributedText?.length ?? 0 == 0
        textStack.addArrangedSubview(detailLabel)

        let play = UIButton(type: .system)
        play.translatesAutoresizingMaskIntoConstraints = false
        play.backgroundColor = .tertiarySystemFill
        play.layer.cornerRadius = Self.playButtonSize / 2
        play.tintColor = Self.playGlyphColor
        applyPlaySymbol(to: play, isPlaying: playingLineIndex == line.displayIndex)
        let displayIndex = line.displayIndex
        play.addAction(UIAction { [weak self] _ in
            self?.onToggleLinePlayback?(displayIndex)
        }, for: .touchUpInside)
        playButtons[displayIndex] = play

        row.addSubview(textStack)
        row.addSubview(play)

        var trailingAnchorForText = play.leadingAnchor
        var constraints: [NSLayoutConstraint] = []
        if let pattern = line.patterns.first {
            // Whole row opens the grammar; the play button keeps its own tap.
            let opener = UIControl()
            opener.translatesAutoresizingMaskIntoConstraints = false
            opener.isAccessibilityElement = true
            opener.accessibilityLabel = [line.japanese, pattern.label, pattern.meaning]
                .compactMap { $0 }
                .joined(separator: ", ")
            opener.accessibilityTraits = .button
            opener.accessibilityHint = "Opens the grammar explanation"
            let ref = pattern.ref
            opener.addAction(UIAction { [weak self] _ in
                self?.onSelectPattern?(ref)
            }, for: .touchUpInside)
            opener.addAction(UIAction { [weak opener] _ in
                opener?.backgroundColor = UIColor.label.withAlphaComponent(0.06)
            }, for: [.touchDown, .touchDragEnter])
            opener.addAction(UIAction { [weak opener] _ in
                UIView.animate(withDuration: 0.2) { opener?.backgroundColor = .clear }
            }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            opener.layer.cornerRadius = 10
            row.insertSubview(opener, at: 0)

            let chevron = UIImageView(image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            ))
            chevron.tintColor = .tertiaryLabel
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            row.addSubview(chevron)
            trailingAnchorForText = chevron.leadingAnchor
            constraints += [
                opener.topAnchor.constraint(equalTo: row.topAnchor, constant: -6),
                opener.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: 6),
                opener.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -8),
                opener.trailingAnchor.constraint(equalTo: play.leadingAnchor, constant: -4),
                chevron.trailingAnchor.constraint(equalTo: play.leadingAnchor, constant: -12),
                chevron.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            ]
        }

        constraints += [
            textStack.topAnchor.constraint(equalTo: row.topAnchor),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchorForText, constant: -10),

            play.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            play.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            play.widthAnchor.constraint(equalToConstant: Self.playButtonSize),
            play.heightAnchor.constraint(equalToConstant: Self.playButtonSize),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.playButtonSize),
        ]
        NSLayoutConstraint.activate(constraints)
        return row
    }

    /// The pattern's surface in the accent color — the part worth a second look.
    private func japaneseText(for line: RolePlayRecap.Line) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: line.japanese,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.label,
            ]
        )
        if let range = line.highlightRange,
           NSMaxRange(range) <= (line.japanese as NSString).length {
            text.addAttributes([
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: Self.accentColor,
            ], range: range)
        }
        return text
    }

    private func patternDetailText(_ pattern: RolePlayRecap.Pattern) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: pattern.label,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: Self.accentColor,
            ]
        )
        if let meaning = pattern.meaning, !meaning.isEmpty {
            text.append(NSAttributedString(
                string: "  ·  \(meaning)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            ))
        }
        return text
    }

    private func applyPlaySymbol(to button: UIButton, isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        button.setImage(
            UIImage(systemName: isPlaying ? "pause.fill" : "play.fill", withConfiguration: config),
            for: .normal
        )
        button.accessibilityLabel = isPlaying ? "Pause" : "Play this line"
    }
}
