//
//  TutorOnboardingPracticeSteps.swift
//  shizen
//
//  A scripted roleplay with a fake mic, a fake "AI" plan that writes itself
//  on timers, and the send-off. Nothing here calls a model or records audio.
//

import NNKit
import UIKit

// MARK: - Roleplay

final class TutorRoleplayStepViewController: TutorStepViewController {

    override var progressBeatCount: Int { session.goal.rounds.count + 1 }

    private var chat: TutorChatView?
    private let dock = UIStackView()
    private var rounds: [TutorRound] = []
    private var isAwaitingReply = false

    override func buildStage() {
        let goal = session.goal
        setupOnboarding(
            title: "Your first scene",
            subtitle: "\(goal.emoji) \(goal.sceneTitle) · Hana plays the \(goal.partnerRole)"
        )
        rounds = goal.rounds
        isAwaitingReply = false

        let chat = TutorChatView(timeline: timeline)
        self.chat = chat

        dock.arrangedSubviews.forEach { $0.removeFromSuperview() }
        dock.axis = .vertical
        dock.spacing = 10
        dock.translatesAutoresizingMaskIntoConstraints = false

        stage.addSubview(chat)
        stage.addSubview(dock)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -8),

            dock.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 20),
            dock.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -20),
            dock.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)
    }

    override func play() {
        let role = session.goal.partnerRole
        timeline.after(0.35) { [weak self] in
            self?.chat?.play([
                .tutorText("I'll play the \(role). Pick a reply, then say it out loud. I'm listening."),
            ]) { [weak self] in
                self?.playRound(0)
            }
        }
    }

    private func playRound(_ index: Int) {
        guard rounds.indices.contains(index) else {
            finishScene()
            return
        }
        let round = rounds[index]
        chat?.play([.tutorJapanese(round.prompt)]) { [weak self] in
            self?.offerReplies(for: round, index: index)
        }
    }

    private func offerReplies(for round: TutorRound, index: Int) {
        let chips = round.replies.map { reply in
            let chip = TutorReplyChip(line: TutorLine(
                session.personalize(reply.japanese),
                session.personalize(reply.english)
            ))
            chip.tag = index
            chip.addTarget(self, action: #selector(replyTapped(_:)), for: .touchUpInside)
            return chip
        }
        setDock(chips)
        slideIn(chips, stagger: 0.07)
        isAwaitingReply = true
    }

    @objc private func replyTapped(_ chip: TutorReplyChip) {
        guard isAwaitingReply, rounds.indices.contains(chip.tag) else { return }
        isAwaitingReply = false
        chip.isChosen = true
        playSelectionHaptic()

        let others = dock.arrangedSubviews.filter { $0 !== chip }
        UIView.animate(withDuration: AnimationDefaults.fastDuration) {
            others.forEach { $0.alpha = 0 }
        }

        let round = rounds[chip.tag]
        let index = chip.tag
        let line = chip.line
        timeline.after(0.3) { [weak self] in
            self?.listen(to: line, round: round, index: index)
        }
    }

    private func listen(to line: TutorLine, round: TutorRound, index: Int) {
        let listening = TutorListeningView(prompt: line.japanese)
        setDock([listening])
        slideIn([listening])
        HapticsHelper.lightHaptic()

        timeline.after(1.8) { [weak self] in
            guard let self else { return }
            self.setDock([])
            self.chat?.append(.userJapanese(line))
            self.celebrate(round.praise)
            self.advanceProgressBeat(to: index + 1)
            self.timeline.after(1.1) { [weak self] in
                self?.playRound(index + 1)
            }
        }
    }

    private func setDock(_ views: [UIView]) {
        dock.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { dock.addArrangedSubview($0) }
        stage.layoutIfNeeded()
        chat?.scrollToBottom(animated: true)
    }

    private func celebrate(_ praise: String) {
        let badge = EncouragementBadgeView(text: praise, fillColor: TutorPalette.sakura, textColor: .white)
        stage.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            badge.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -28),
        ])
        stage.layoutIfNeeded()
        badge.prepareForCascadeEntry()

        let pop = UIViewPropertyAnimator(
            duration: 0.5,
            controlPoint1: AnimationDefaults.overshootControlPoint1,
            controlPoint2: AnimationDefaults.overshootControlPoint2
        ) {
            badge.alpha = 1
            badge.transform = .identity
        }
        pop.addCompletion { _ in badge.playEntryShimmer() }
        pop.startAnimation()
        HapticsHelper.successHaptic()
        explodeEmoji(from: badge)

        timeline.after(1.0) {
            UIView.animate(withDuration: 0.25, animations: {
                badge.alpha = 0
                badge.transform = CGAffineTransform(translationX: 0, y: -16)
            }, completion: { _ in
                badge.removeFromSuperview()
            })
        }
    }

    private func finishScene() {
        let goal = session.goal
        chat?.play([.tutorJapanese(goal.closing)]) { [weak self] in
            guard let self, let chat = self.chat else { return }
            let notes = TutorNotesCard()
            chat.appendCustom(notes)
            self.timeline.after(0.5) { [weak self] in
                self?.stream(goal.tip, into: notes.tipLabel, onTick: {
                    chat.scrollToBottom(animated: false)
                }) { [weak self] in
                    self?.revealCTA("Next")
                }
            }
        }
    }
}

/// End-of-scene feedback card; the tip streams in like a model response.
final class TutorNotesCard: UIView {

    let tipLabel = UILabel()

    init(
        title: String = "Hana's notes",
        checks checkTexts: [String] = ["Understood on the first try", "Natural word order", "Clear pronunciation"]
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let sparkle = UIImageView(image: UIImage(systemName: "sparkles"))
        sparkle.tintColor = .systemYellow
        let header = UILabel()
        header.text = title
        header.font = .systemFont(ofSize: 15, weight: .bold)
        let headerRow = UIStackView(arrangedSubviews: [sparkle, header])
        headerRow.spacing = 6
        headerRow.alignment = .center

        let checks = checkTexts.map(Self.checkRow)

        let tipTitle = UILabel()
        tipTitle.text = "TRY NEXT"
        tipTitle.font = .systemFont(ofSize: 12, weight: .bold)
        tipTitle.textColor = .secondaryLabel

        tipLabel.font = .preferredFont(forTextStyle: .subheadline)
        tipLabel.textColor = .label
        tipLabel.numberOfLines = 0

        var arranged: [UIView] = [headerRow]
        arranged += checks
        arranged += [tipTitle, tipLabel]
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: headerRow)
        if let lastCheck = checks.last {
            stack.setCustomSpacing(16, after: lastCheck)
        }
        stack.setCustomSpacing(4, after: tipTitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func checkRow(_ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = .systemGreen
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 8
        row.alignment = .center
        return row
    }
}

// MARK: - Plan

class TutorPlanStepViewController: TutorStepViewController {

    override var progressBeatCount: Int { 2 }

    // MARK: Content hooks (the pick, fake generation, and plan reveal stay shared)

    var planPicker: (title: String, subtitle: String, options: [(minutes: Int, text: String)]) {
        (
            "How much time can you give Hana?",
            "Even five minutes a day adds up fast.",
            [
                (5, "☕️  5 min a day · Quick bite"),
                (10, "🍵  10 min a day · Steady"),
                (20, "🔥  20 min a day · Serious"),
            ]
        )
    }

    var planGeneratingTitle: String {
        "Writing your plan…"
    }

    var planGeneratingSubtitle: String {
        "Hana is building week one from your answers."
    }

    var planChecklist: [String] {
        [
            "Reading your answers",
            "Writing scenes for \(session.goal.title.lowercased())",
            "Tuning every line to “\(session.level.title)”",
            "Pacing it for \(session.minutesPerDay) minutes a day",
        ]
    }

    var planReadyHeader: (title: String, subtitle: String) {
        ("Week one is ready.", "Written for \(session.displayName) · \(session.minutesPerDay) min a day")
    }

    var planCard: TutorPlanCard.Content {
        TutorPlanCard.Content(
            eyebrow: "WEEK 1",
            title: "\(session.goal.emoji) \(session.goal.title)",
            rows: session.goal.weekPlan.enumerated().map { index, scene in
                TutorPlanCard.Row(label: "Day \(index + 1)", title: scene, detail: "\(session.minutesPerDay) min")
            }
        )
    }

    var planSummary: String {
        "Your first scene, \(session.goal.sceneTitle.lowercased()), uses lines you'll actually need, "
            + "shown \(session.level.planPhrase). Every session ends with you saying it out loud to Hana."
    }

    /// Runs after the time pick, before the fake generation; call `proceed` to continue.
    /// `options` is the picked card stack, for subclasses that want to clear it first.
    func playInterlude(clearing options: UIView, proceed: @escaping () -> Void) {
        proceed()
    }

    /// Runs as the checklist starts building the plan, after the pick and interlude.
    func willGeneratePlan() {}

    /// Runs once the plan card has fully revealed, before the CTA; call `done` to show it.
    func playAfterPlan(below card: UIView, done: @escaping () -> Void) {
        done()
    }

    /// Shows the CTA with `title`; tapping it runs `next` instead of leaving the step.
    func continueOnCTA(_ title: String, _ next: @escaping () -> Void) {
        pendingCTAContinue = next
        revealCTA(title)
    }

    private var options: [(minutes: Int, text: String)] = []
    private var pendingCTAContinue: (() -> Void)?

    private var optionCards: [OnboardingSummaryCard] = []
    private let optionsStack = UIStackView()
    private var isLocked = false

    override func buildStage() {
        let picker = planPicker
        setupOnboarding(title: picker.title, subtitle: picker.subtitle)
        options = picker.options
        isLocked = false
        pendingCTAContinue = nil

        optionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        optionsStack.axis = .vertical
        optionsStack.spacing = 12
        optionsStack.alpha = 1
        optionsStack.transform = .identity
        optionsStack.translatesAutoresizingMaskIntoConstraints = false

        optionCards = options.enumerated().map { index, option in
            let card = OnboardingSummaryCard()
            card.text = option.text
            card.tag = index
            card.alpha = 0
            card.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            optionsStack.addArrangedSubview(card)
            return card
        }

        stage.addSubview(optionsStack)
        NSLayoutConstraint.activate([
            optionsStack.topAnchor.constraint(equalTo: stage.topAnchor, constant: 16),
            optionsStack.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            optionsStack.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),
        ])
    }

    override func play() {
        slideIn(optionCards, stagger: 0.07, initialDelay: 0.15)
    }

    @objc private func optionTapped(_ card: OnboardingSummaryCard) {
        guard !isLocked else { return }
        isLocked = true
        card.isChosen = true
        session.minutesPerDay = options[card.tag].minutes
        playSelectionHaptic()
        explodeEmoji(from: card, preset: .tiny)
        advanceProgressBeat(to: 1)
        timeline.after(0.35) { [weak self] in
            guard let self else { return }
            self.playInterlude(clearing: self.optionsStack) { [weak self] in
                self?.generate()
            }
        }
    }

    override func ctaTapped() {
        guard let next = pendingCTAContinue else {
            super.ctaTapped()
            return
        }
        pendingCTAContinue = nil
        hideCTA(animated: true)
        next()
    }

    private func generate() {
        willGeneratePlan()
        UIView.animate(withDuration: AnimationDefaults.standardDuration) {
            self.optionsStack.alpha = 0
            self.optionsStack.transform = CGAffineTransform(translationX: 0, y: -16)
        }
        transitionHeader(title: planGeneratingTitle, subtitle: planGeneratingSubtitle)

        let rows = planChecklist.map { TutorChecklistRow(text: $0) }

        let checklist = UIStackView(arrangedSubviews: rows)
        checklist.axis = .vertical
        checklist.spacing = 18
        checklist.translatesAutoresizingMaskIntoConstraints = false
        rows.forEach { $0.alpha = 0 }
        stage.addSubview(checklist)
        NSLayoutConstraint.activate([
            checklist.topAnchor.constraint(equalTo: stage.topAnchor, constant: 28),
            checklist.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 36),
            checklist.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -36),
        ])

        timeline.after(0.4) { [weak self] in
            self?.runChecklist(rows, index: 0, container: checklist)
        }
    }

    private func runChecklist(_ rows: [TutorChecklistRow], index: Int, container: UIView) {
        guard rows.indices.contains(index) else {
            timeline.after(0.45) { [weak self] in
                self?.revealPlan(replacing: container)
            }
            return
        }
        let row = rows[index]
        slideIn([row])
        row.startWorking()
        timeline.after(0.7 + Double(index) * 0.12) { [weak self] in
            row.complete()
            HapticsHelper.superLightHaptic()
            self?.timeline.after(0.15) { [weak self] in
                self?.runChecklist(rows, index: index + 1, container: container)
            }
        }
    }

    private func revealPlan(replacing checklist: UIView) {
        UIView.animate(withDuration: AnimationDefaults.standardDuration, animations: {
            checklist.alpha = 0
            checklist.transform = CGAffineTransform(translationX: 0, y: -16)
        }, completion: { _ in
            checklist.removeFromSuperview()
        })
        let readyHeader = planReadyHeader
        transitionHeader(title: readyHeader.title, subtitle: readyHeader.subtitle)
        showPlan { [weak self] in
            self?.revealCTA("Looks good")
        }
    }

    /// Builds and plays the finished plan on the stage, then calls `done` to bring in the CTA.
    /// Default: the week card with its summary and rows, then `playAfterPlan`.
    func showPlan(done: @escaping () -> Void) {
        let card = TutorPlanCard(content: planCard)
        stage.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: stage.topAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor),
        ])
        slideIn([card], initialDelay: 0.15)
        HapticsHelper.successHaptic()

        let summary = planSummary
        timeline.after(0.55) { [weak self] in
            self?.stream(summary, into: card.summaryLabel) { [weak self] in
                guard let self else { return }
                self.slideIn(card.dayRows, stagger: 0.08)
                self.timeline.after(0.6) { [weak self] in
                    card.playShimmer(highlightAlpha: 0.35, duration: 0.6)
                    self?.playAfterPlan(below: card, done: done)
                }
            }
        }
    }
}

extension TutorLevel {
    var planPhrase: String {
        switch self {
        case .brandNew: return "in romaji with English underneath"
        case .kana: return "in kana with English underneath"
        case .someKanji: return "in real Japanese with furigana"
        case .conversational: return "in Japanese only"
        }
    }
}

final class TutorChecklistRow: UIView {

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let check = UIImageView(image: UIImage(
        systemName: "checkmark.circle.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    ))
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconSlot = UIView()
        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        check.tintColor = .systemGreen
        check.isHidden = true
        check.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(spinner)
        iconSlot.addSubview(check)

        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconSlot)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconSlot.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSlot.widthAnchor.constraint(equalToConstant: 24),
            iconSlot.heightAnchor.constraint(equalToConstant: 24),
            spinner.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            check.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: iconSlot.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startWorking() {
        spinner.startAnimating()
    }

    func complete() {
        spinner.stopAnimating()
        check.isHidden = false
        check.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction]
        ) {
            self.check.transform = .identity
            self.label.textColor = .label
        }
    }
}

final class TutorPlanCard: UIView {

    struct Row {
        let label: String
        let title: String
        let detail: String?
    }

    struct Content {
        let eyebrow: String
        let title: String
        let rows: [Row]
    }

    let summaryLabel = UILabel()
    private(set) var dayRows: [UIView] = []

    init(content: Content) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let eyebrow = UILabel()
        eyebrow.text = content.eyebrow
        eyebrow.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrow.textColor = .secondaryLabel

        let title = UILabel()
        title.text = content.title
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .label

        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        dayRows = content.rows.map { item in
            let row = Self.dayRow(item)
            row.alpha = 0
            return row
        }

        let arranged: [UIView] = [eyebrow, title, summaryLabel] + dayRows
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(2, after: eyebrow)
        stack.setCustomSpacing(16, after: summaryLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func dayRow(_ item: Row) -> UIView {
        let pill = UILabel()
        pill.text = item.label
        pill.font = .systemFont(ofSize: 12, weight: .bold)
        pill.textAlignment = .center
        pill.backgroundColor = ExperimentPalette.highlightFill
        pill.layer.cornerRadius = 11
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 52),
            pill.heightAnchor.constraint(equalToConstant: 22),
        ])

        let title = UILabel()
        title.text = item.title
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.textColor = .label
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let duration = UILabel()
        duration.text = item.detail
        duration.isHidden = item.detail == nil
        duration.font = .preferredFont(forTextStyle: .footnote)
        duration.textColor = .secondaryLabel
        duration.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [pill, title, duration])
        row.spacing = 10
        row.alignment = .center
        return row
    }
}

// MARK: - Ready

class TutorReadyStepViewController: TutorStepViewController {

    override var hidesOnboardingBackButton: Bool { true }

    // MARK: Content hooks

    var readySubtitle: String { "Your first scene is written and waiting." }
    var readyBadge: String { "はじめよう！" }
    var readyBadgeEnglish: String { "Let's begin!" }
    var readyCapsules: [String] {
        ["\(session.goal.emoji)  \(session.goal.title)", "📖  \(session.level.title)", "⏱  \(session.minutesPerDay) min a day"]
    }
    var readyFarewell: TutorLine { session.goal.farewell }
    var readyCTA: String { "Start speaking" }

    private var badge: EncouragementBadgeView?
    private var capsules: [UIView] = []
    private var farewell: UIView?

    override func buildStage() {
        setupOnboarding(title: "You're ready, \(session.displayName).", subtitle: readySubtitle)

        let badge = EncouragementBadgeView(text: readyBadge, fillColor: TutorPalette.sakura, textColor: .white)
        badge.alpha = 0
        self.badge = badge

        capsules = readyCapsules.map { TutorCapsuleLabel(text: $0) }
        capsules.forEach { $0.alpha = 0 }

        let capsuleStack = UIStackView(arrangedSubviews: capsules)
        capsuleStack.axis = .vertical
        capsuleStack.alignment = .center
        capsuleStack.spacing = 10
        capsuleStack.translatesAutoresizingMaskIntoConstraints = false

        let farewell = TutorChatView.tutorRow(
            content: TutorChatView.japaneseColumn(
                readyFarewell,
                side: .leading,
                onBreakdown: breakdownAction(for: readyFarewell)
            ),
            avatar: session.showsMascot ? .mascot : .emoji
        )
        farewell.translatesAutoresizingMaskIntoConstraints = false
        farewell.alpha = 0
        self.farewell = farewell

        // The badge is Japanese too, so it swipes open like any line.
        let badgeHost: UIView = breakdownAction(for: TutorLine(readyBadge, readyBadgeEnglish))
            .map { TutorChatView.dissectible(badge, onBreakdown: $0) } ?? badge
        stage.addSubview(badgeHost)
        stage.addSubview(capsuleStack)
        stage.addSubview(farewell)

        NSLayoutConstraint.activate([
            badgeHost.topAnchor.constraint(equalTo: stage.topAnchor, constant: 40),
            badgeHost.centerXAnchor.constraint(equalTo: stage.centerXAnchor),

            capsuleStack.topAnchor.constraint(equalTo: badgeHost.bottomAnchor, constant: 32),
            capsuleStack.centerXAnchor.constraint(equalTo: stage.centerXAnchor),

            farewell.topAnchor.constraint(equalTo: capsuleStack.bottomAnchor, constant: 36),
            farewell.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            farewell.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),
        ])
    }

    override func play() {
        timeline.after(0.2) { [weak self] in
            self?.popBadge()
        }
        slideIn(capsules, stagger: 0.08, initialDelay: 0.55)
        timeline.after(1.0) { [weak self] in
            guard let self, let farewell = self.farewell else { return }
            self.slideIn([farewell])
            HapticsHelper.superLightHaptic()
        }
        timeline.after(1.5) { [weak self] in
            guard let self else { return }
            self.revealCTA(self.readyCTA)
        }
    }

    override func ctaTapped() {
        coordinator?.finishSetup()
    }

    private func popBadge() {
        guard let badge else { return }
        stage.layoutIfNeeded()
        badge.prepareForCascadeEntry()
        let pop = UIViewPropertyAnimator(
            duration: 0.6,
            controlPoint1: AnimationDefaults.overshootControlPoint1,
            controlPoint2: AnimationDefaults.overshootControlPoint2
        ) {
            badge.alpha = 1
            badge.transform = .identity
        }
        pop.addCompletion { _ in badge.playEntryShimmer() }
        pop.startAnimation()
        HapticsHelper.successHaptic()
        explodeEmoji(from: badge, preset: .medium)
    }
}
