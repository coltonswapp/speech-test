//
//  NaturalTeamNoteStepViewController.swift
//  shizen
//
//  A short, personal note from the team right before the paywall: why Shizen
//  is a subscription, in a letter's voice rather than a sales pitch. No prices,
//  no feature list, no skip; Continue hands off to the paywall.
//
//  Not in `NaturalOnboardingFlow` yet (SHZ-40). Review it from
//  Settings → Playground → Team note.
//

import NNKit
import UIKit

// MARK: - Copy

/// Everything the note says, in one place so it's easy to edit.
struct NaturalTeamNoteCopy {

    enum Avatar {
        case initials(String)
        /// Hana herself, standing free beside the team rather than in a circle.
        case hana
    }

    var title: String
    var avatars: [Avatar]
    var paragraphs: [String]
    /// The Hana variant: her setup line, then the team speaks for itself.
    var hanaIntro: String
    var teamName: String
    var teamLines: [String]
    var signature: String
    var cta: String

    static let current = NaturalTeamNoteCopy(
        title: "A quick note from us",
        avatars: [.initials("C"), .hana],
        paragraphs: [
            "Hey — thanks for giving Shizen a try.",
            "We're a tiny team building the Japanese app we always wanted: real conversations, natural voices, and lessons that actually stick.",
            "Shizen has no ads and never sells your data. Subscriptions are how we keep the lights on and keep making new dialogues every week.",
            "If Shizen helps you, we'd be grateful for your support.",
        ],
        hanaIntro: "Our team has something they want to share with you…",
        teamName: "The Shizen team",
        teamLines: [
            "We're a tiny team building the Japanese app we always wanted: real conversations, natural voices, and lessons that actually stick.",
            "Shizen has no ads and never sells your data.",
            "Subscriptions are how we keep the lights on and keep making new dialogues every week.",
            "If Shizen helps you, we'd be so grateful for your support.",
        ],
        signature: "— Colton & the Shizen team",
        cta: "Continue"
    )
}

// MARK: - Team note

final class NaturalTeamNoteStepViewController: NaturalStepViewController {

    /// Past setup, so there's no way back from here; the only way on is Continue.
    override var hidesOnboardingBackButton: Bool { true }

    /// Replaces the hand-off to the coordinator; the playground uses it to open the paywalls.
    var continueHandler: (() -> Void)?

    private let note: NaturalTeamNoteCopy
    private var letter: NaturalTeamNoteLetterView?

    init(session: NaturalOnboardingSession, note: NaturalTeamNoteCopy = .current) {
        self.note = note
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildStage() {
        setupOnboarding(title: note.title)

        // Scrolls so the largest text sizes and the SE still fit above the button.
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(scrollView)

        let letter = NaturalTeamNoteLetterView(note: note)
        letter.alpha = 0
        letter.lines.forEach { $0.alpha = 0 }
        scrollView.addSubview(letter)
        self.letter = letter

        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: stage.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            letter.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            letter.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            letter.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: OnboardingChrome.horizontalInset),
            letter.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -OnboardingChrome.horizontalInset),
            letter.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -2 * OnboardingChrome.horizontalInset
            ),
        ])
        scrollUnderHeader(scrollView, scrollView: scrollView)
    }

    override func play() {
        guard let letter else { return }
        timeline.after(0.15) { [weak self] in
            self?.slideIn([letter])
        }
        timeline.after(0.35) { [weak self] in
            self?.slideIn(letter.lines, stagger: 0.18)
        }
        let linesLanded = 0.35 + 0.18 * Double(letter.lines.count) + 0.3
        timeline.after(linesLanded) {
            HapticsHelper.superLightHaptic()
        }
        timeline.after(linesLanded + 0.3) { [weak self] in
            guard let self else { return }
            self.revealCTA(self.note.cta)
        }
    }

    override func ctaTapped() {
        HapticsHelper.lightHaptic()
        if let continueHandler {
            continueHandler()
        } else {
            super.ctaTapped()
        }
    }
}

// MARK: - Team note, introduced by Hana

/// The same note as a chat: Hana, on the left, says the team has something to share. Then the
/// team speaks from the right, as their own bubbles, and signs off. Then Continue.
final class NaturalTeamNoteHanaStepViewController: NaturalStepViewController {

    override var hidesOnboardingBackButton: Bool { true }

    /// Replaces the hand-off to the coordinator; the playground uses it to open the paywalls.
    var continueHandler: (() -> Void)?

    private let note: NaturalTeamNoteCopy
    private var chat: TutorChatView?

    init(session: NaturalOnboardingSession, note: NaturalTeamNoteCopy = .current) {
        self.note = note
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildStage() {
        setupOnboarding(title: note.title)

        // Always the moving mascot, whatever the session's default avatar is.
        let chat = TutorChatView(timeline: timeline, avatars: .mascot)
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        self.chat = chat
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)
    }

    override func play() {
        guard let chat else { return }
        timeline.after(0.35) { [weak self] in
            guard let self else { return }
            chat.play([.tutorText(self.note.hanaIntro)]) { [weak self] in
                // A beat to let "something to share" land before the team speaks.
                self?.timeline.after(0.9) { [weak self] in
                    guard let self else { return }
                    chat.appendCustom(Self.teamHeader(self.note.teamName))
                    self.playTeamLines(self.note.teamLines[...])
                }
            }
        }
    }

    /// One team bubble at a time, paced by length since the team has no typing indicator.
    private func playTeamLines(_ lines: ArraySlice<String>) {
        guard let line = lines.first else {
            timeline.after(0.5) { [weak self] in self?.signOff() }
            return
        }
        let pause = min(1.5, 0.5 + Double(line.count) * 0.01)
        timeline.after(pause) { [weak self] in
            guard let self, let chat = self.chat else { return }
            chat.appendCustom(Self.teamRow(line))
            HapticsHelper.superLightHaptic()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: line)
            }
            self.playTeamLines(lines.dropFirst())
        }
    }

    private func signOff() {
        guard let chat else { return }
        let signature = UILabel()
        signature.text = note.signature
        signature.accessibilityLabel = note.signature.replacingOccurrences(of: "— ", with: "From ")
        signature.font = NaturalTeamNoteLetterView.serifFont(size: 17, textStyle: .body, italic: true, traits: traitCollection)
        signature.adjustsFontForContentSizeCategory = true
        signature.textColor = .secondaryLabel
        signature.textAlignment = .right
        signature.numberOfLines = 0
        chat.appendCustom(signature)
        timeline.after(0.6) { [weak self] in
            guard let self else { return }
            self.revealCTA(self.note.cta)
        }
    }

    override func ctaTapped() {
        HapticsHelper.lightHaptic()
        if let continueHandler {
            continueHandler()
        } else {
            super.ctaTapped()
        }
    }

    // MARK: Team rows

    /// "The Shizen team" with its initials avatar, on the right, over the team's first bubble.
    private static func teamHeader(_ name: String) -> UIView {
        let avatar = UILabel()
        avatar.text = "C"
        avatar.font = .systemFont(ofSize: 13, weight: .bold)
        avatar.textColor = .black
        avatar.textAlignment = .center
        avatar.backgroundColor = .systemYellow
        avatar.layer.cornerRadius = 11
        avatar.layer.masksToBounds = true
        avatar.isAccessibilityElement = false
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = name
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [label, avatar])
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIView()
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 22),
            avatar.heightAnchor.constraint(equalToConstant: 22),
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
        ])
        return row
    }

    /// A trailing bubble like a user line, but at body weight: it's the team talking, not you.
    private static func teamRow(_ text: String) -> UIView {
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: text,
            font: .systemFont(ofSize: 16, weight: .regular),
            side: .trailing,
            showsTail: true
        )
        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return TutorChatView.userRow(content: bubble)
    }
}

// MARK: - Letter

/// The note itself: a paper-like card with the team's avatars, the paragraphs in a serif, and the sign-off.
final class NaturalTeamNoteLetterView: UIView {

    private static let avatarSize: CGFloat = 40
    private static let avatarOverlap: CGFloat = 10
    private static let avatarRingWidth: CGFloat = 2.5

    /// Paragraphs, then the signature, in reading order; the step reveals them one by one.
    let lines: [UIView]

    private let note: NaturalTeamNoteCopy
    private let paragraphLabels: [UILabel]
    private let signatureLabel = UILabel()
    private var avatarViews: [UIView] = []

    init(note: NaturalTeamNoteCopy) {
        self.note = note
        paragraphLabels = note.paragraphs.map { _ in UILabel() }
        lines = paragraphLabels + [signatureLabel]
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth

        (paragraphLabels + [signatureLabel]).forEach { label in
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        signatureLabel.accessibilityLabel = note.signature.replacingOccurrences(of: "— ", with: "From ")

        let stack = UIStackView(arrangedSubviews: [makeAvatarRow()] + paragraphLabels + [signatureLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[0])
        if let last = paragraphLabels.last {
            stack.setCustomSpacing(22, after: last)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        applyText()
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (letter: NaturalTeamNoteLetterView, _) in
            letter.applyChrome()
        }
        // Attributed text doesn't rescale on its own, so rebuild it when the text size changes.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (letter: NaturalTeamNoteLetterView, _) in
            letter.applyText()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyText() {
        let traits = traitCollection
        let body = Self.serifFont(size: 17, textStyle: .body, italic: false, traits: traits)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        for (label, text) in zip(paragraphLabels, note.paragraphs) {
            label.attributedText = NSAttributedString(string: text, attributes: [
                .font: body,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ])
        }
        signatureLabel.font = Self.serifFont(size: 17, textStyle: .body, italic: true, traits: traits)
        signatureLabel.textColor = .secondaryLabel
        signatureLabel.text = note.signature
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
        // The ring matches the card so overlapping avatars read as separate circles.
        let ring = ExperimentPalette.cardSurface.resolvedColor(with: traitCollection).cgColor
        avatarViews.forEach { $0.layer.borderColor = ring }
    }

    // MARK: Avatars

    private func makeAvatarRow() -> UIView {
        let row = UIView()
        row.isAccessibilityElement = false
        avatarViews = note.avatars.map(makeAvatar)
        var previous: UIView?
        // Later avatars tuck under earlier ones, like a stack of photos.
        for avatar in avatarViews.reversed() {
            row.addSubview(avatar)
        }
        for avatar in avatarViews {
            NSLayoutConstraint.activate([
                avatar.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
                avatar.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
                avatar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                previous.map {
                    avatar.leadingAnchor.constraint(equalTo: $0.trailingAnchor, constant: -Self.avatarOverlap)
                } ?? avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -Self.avatarRingWidth),
            ])
            previous = avatar
        }
        return row
    }

    private func makeAvatar(_ avatar: NaturalTeamNoteCopy.Avatar) -> UIView {
        if case .hana = avatar {
            return makeHana()
        }

        let circle = UIView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.layer.cornerRadius = Self.avatarSize / 2
        circle.layer.borderWidth = Self.avatarRingWidth
        circle.clipsToBounds = true

        let label = UILabel()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        switch avatar {
        case .initials(let initials):
            circle.backgroundColor = .systemYellow
            label.text = initials
            label.font = .systemFont(ofSize: 17, weight: .bold)
            label.textColor = .black
        case .hana:
            break
        }
        circle.addSubview(label)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            circle.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            label.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
        ])
        return circle
    }

    /// Same setup as Hana in the onboarding chat: pink, no haptics, no taps, smiling.
    private func makeHana() -> UIView {
        let mascot = TutorChatView.makeMascot()
        mascot.set(MascotPreset.happy.expression, animated: false)
        mascot.isAccessibilityElement = false
        mascot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: TutorChatView.mascotSize),
            mascot.heightAnchor.constraint(equalToConstant: TutorChatView.mascotSize),
        ])
        return mascot
    }

    /// The system serif at `size`, scaled with Dynamic Type for `textStyle`.
    static func serifFont(size: CGFloat, textStyle: UIFont.TextStyle, italic: Bool, traits: UITraitCollection) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        descriptor = descriptor.withDesign(.serif) ?? descriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor
        }
        let base = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
    }
}

// MARK: - Playground

/// Settings → Playground → Team note (letter or Hana): the note full screen with a fresh session. Continue pushes
/// the paywall picker so the hand-off can be felt; the close button exists only here, not in the flow.
final class NaturalTeamNotePlaygroundController: UINavigationController, UINavigationControllerDelegate {

    enum Variant {
        case letter
        case hana
    }

    init(variant: Variant = .letter) {
        super.init(nibName: nil, bundle: nil)
        let session = NaturalOnboardingSession()
        let note: NaturalStepViewController
        switch variant {
        case .letter:
            let letter = NaturalTeamNoteStepViewController(session: session)
            letter.continueHandler = { [weak self] in self?.showPaywalls() }
            note = letter
        case .hana:
            let hana = NaturalTeamNoteHanaStepViewController(session: session)
            hana.continueHandler = { [weak self] in self?.showPaywalls() }
            note = hana
        }
        setViewControllers([note], animated: false)
        setNavigationBarHidden(true, animated: false)
        modalPresentationStyle = .fullScreen
        delegate = self

        let closeButton = OnboardingChrome.makeCircularIconButton(symbolName: "xmark")
        closeButton.accessibilityLabel = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        note.view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: note.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: note.view.leadingAnchor, constant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func showPaywalls() {
        let paywalls = PaywallExperimentViewController()
        paywalls.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        pushViewController(paywalls, animated: true)
    }

    /// The bar only shows on the paywall picker, where it carries Back and Done.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        setNavigationBarHidden(viewController === viewControllers.first, animated: animated)
    }
}
