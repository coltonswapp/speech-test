//
//  ListenFirstTakeApartStep.swift
//  shizen
//
//  Screen 4 · Now take it apart. One line from the conversation plays as a live
//  meter in its speech bubble (the listen screen's `NaturalDialogueLineView`), the
//  meter turns into the Japanese, an underline draws under
//  each word, and the words cascade out into chips. Tap a chip to see what it means.
//  Hana listens from the bottom, then works while the line splits.
//

import AVFoundation
import InteractionKit
import NNKit
import UIKit

final class ListenFirstTakeApartStepViewController: ListenFirstStepViewController {

    private let voice = NaturalVoicePlayer()
    private let meters = NaturalMeterDriver()
    private var lineView: NaturalDialogueLineView?
    private var underlines: ListenFirstTokenUnderlines?
    private var chips: [ListenFirstTokenChip] = []
    private let chipRows = UIStackView()
    private let meaningLabel = UILabel()
    private let hanaSpot = UIView()
    /// The chip whose definition popover is open.
    private var selectedChip: Int?

    private var line: ListenFirstLine { ListenFirstContent.conversation[ListenFirstContent.takeApartLine] }
    private var tokens: [NaturalPiece] { ListenFirstContent.takeApartTokens }
    /// One chip per distinct word, in first-seen order, with the token it came from.
    /// A repeated word (like the second の) still gets underlined but no second chip.
    private var chipTokens: [(tokenIndex: Int, piece: NaturalPiece)] {
        var seen = Set<String>()
        return tokens.enumerated().compactMap { index, piece in
            seen.insert(piece.japanese).inserted ? (index, piece) : nil
        }
    }

    /// Looking up at the bubble while the line plays.
    private static let hanaListening = MascotExpression([.lookY: -0.75])

    override func buildStage() {
        setupOnboarding(title: "Now, take it apart.", subtitle: "Here are the words. Tap one to explore it.")
        selectedChip = nil
        chips = []

        // The same speech bubble as the listen screen: a live meter that reveals its Japanese.
        let lineView = NaturalDialogueLineView(
            speaker: ListenFirstContent.speakers[line.speaker],
            side: line.speaker == 0 ? .leading : .trailing,
            japanese: listen.defaultText(line),
            english: line.english
        )
        lineView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(lineTapped)))
        // Hidden until its slide-in, so it doesn't sit on screen during the push and then pop out.
        lineView.alpha = 0
        self.lineView = lineView
        underlines = ListenFirstTokenUnderlines(label: lineView.transcriptLabel, tokens: tokens.map(\.japanese))

        chipRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chipRows.axis = .vertical
        chipRows.alignment = .center
        chipRows.spacing = 8

        meaningLabel.font = .preferredFont(forTextStyle: .subheadline)
        meaningLabel.textColor = .secondaryLabel
        meaningLabel.textAlignment = .center
        meaningLabel.numberOfLines = 0
        meaningLabel.text = " "
        meaningLabel.alpha = 0

        hanaSpot.isUserInteractionEnabled = false
        // Swipes right into the line's breakdown, like every other line.
        let lineHost: UIView = breakdownAction(for: TutorLine(line.japanese, line.english))
            .map { TutorChatView.dissectible(lineView, onBreakdown: $0) } ?? lineView
        for subview in [lineHost, chipRows, meaningLabel, hanaSpot] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            lineHost.topAnchor.constraint(equalTo: stage.topAnchor, constant: 32),
            lineHost.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 20),
            lineHost.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -20),

            chipRows.topAnchor.constraint(equalTo: lineHost.bottomAnchor, constant: 28),
            chipRows.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            chipRows.leadingAnchor.constraint(greaterThanOrEqualTo: stage.leadingAnchor, constant: 20),

            meaningLabel.topAnchor.constraint(equalTo: chipRows.bottomAnchor, constant: 16),
            meaningLabel.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 32),
            meaningLabel.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -32),

            hanaSpot.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            hanaSpot.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -8),
            hanaSpot.widthAnchor.constraint(equalToConstant: 110),
            hanaSpot.heightAnchor.constraint(equalToConstant: 110),
        ])
    }

    override func hanaStageDidAppear(firstTime: Bool) {
        hanaStage?.dock(at: hanaSpot, expression: Self.hanaListening)
    }

    override func play() {
        if let lineView {
            slideIn([lineView], initialDelay: 0.2)
        }
        timeline.after(0.7) { [weak self] in self?.listenToLine() }
    }

    override func resetStage() {
        stopPlayback()
        super.resetStage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
        closeDefinition()
    }

    /// Keeps the underlines on their words if the bubble lays out again (e.g. the English
    /// settling in under it).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        underlines?.relayout()
    }

    // MARK: Beats

    /// The line plays as a live meter; when it ends, the meter turns into the words.
    private func listenToLine() {
        guard let lineView else { return }
        if !Self.reducesMotion {
            meters.start { [weak self] in
                guard let self else { return }
                lineView.push(level: self.voice.level)
            }
        }
        voice.play(ListenFirstContent.lineClip(at: ListenFirstContent.takeApartLine)) { [weak self] in
            guard let self else { return }
            self.meters.stop()
            lineView.rest()
            self.timeline.after(0.25) { [weak self] in self?.revealText() }
        }
    }

    private func revealText() {
        guard let lineView else { return }
        lineView.reveal(showsEnglish: true, animated: !Self.reducesMotion)
        HapticsHelper.superLightHaptic()
        hanaStage?.mascot.set(MascotPreset.working.expression)
        timeline.after(0.6) { [weak self] in self?.drawUnderlines() }
    }

    private func drawUnderlines() {
        guard let underlines else { return }
        let duration = underlines.draw(animated: !Self.reducesMotion)
        timeline.after(duration + 0.25) { [weak self] in self?.cascadeChips() }
    }

    /// Each word leaves its underline and drops into a chip below, left to right.
    private func cascadeChips() {
        guard let underlines else { return }
        let chipTokens = chipTokens
        chips = chipTokens.enumerated().map { chipIndex, entry in
            let chip = ListenFirstTokenChip(text: entry.piece.japanese)
            chip.addAction(UIAction { [weak self] _ in self?.chipTapped(chipIndex) }, for: .touchUpInside)
            return chip
        }
        layoutChipRows(maxWidth: stage.bounds.width - 40)
        stage.layoutIfNeeded()

        let fly = !Self.reducesMotion
        for (index, chip) in chips.enumerated() {
            chip.alpha = 0
            if fly, let start = underlines.tokenCenterInWindow(chipTokens[index].tokenIndex) {
                let end = chip.convert(CGPoint(x: chip.bounds.midX, y: chip.bounds.midY), to: nil)
                chip.transform = CGAffineTransform(translationX: start.x - end.x, y: start.y - end.y)
                    .scaledBy(x: 0.5, y: 0.5)
            }
            UIView.animate(
                springDuration: 0.55,
                bounce: 0.3,
                initialSpringVelocity: 0,
                delay: fly ? Double(index) * 0.07 : 0,
                options: [.allowUserInteraction]
            ) {
                chip.alpha = 1
                chip.transform = .identity
            }
            timeline.after(Double(index) * 0.07 + 0.2) {
                HapticsHelper.superLightHaptic()
            }
        }

        let landed = Double(chips.count) * 0.07 + 0.45
        timeline.after(landed) { [weak self] in
            guard let self else { return }
            self.hanaStage?.mascot.set(MascotPreset.pleased.expression)
            UIView.animate(withDuration: 0.3) { self.meaningLabel.alpha = 1 }
            self.meaningLabel.text = "Tap a word to see what it means."
            self.revealCTA("Next")
        }
    }

    /// Packs chips into centered rows that fit `maxWidth`.
    private func layoutChipRows(maxWidth: CGFloat) {
        chipRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func makeRow() -> UIStackView {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            return row
        }
        var row = makeRow()
        var rowWidth: CGFloat = 0
        for chip in chips {
            let width = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            if rowWidth > 0, rowWidth + 8 + width > maxWidth {
                chipRows.addArrangedSubview(row)
                row = makeRow()
                rowWidth = 0
            }
            row.addArrangedSubview(chip)
            rowWidth += (rowWidth > 0 ? 8 : 0) + width
        }
        chipRows.addArrangedSubview(row)
    }

    // MARK: Explore

    /// Opens the definition popover on the chip (the sentence scrubber's) and marks the
    /// word in the line. Tapping the open chip again closes it.
    /// The first tap also retires the "Tap a word" hint for good.
    private func chipTapped(_ chipIndex: Int) {
        let entries = chipTokens
        guard entries.indices.contains(chipIndex), chips.indices.contains(chipIndex) else { return }
        HapticsHelper.lightHaptic()
        guard selectedChip != chipIndex else {
            closeDefinition()
            return
        }
        selectedChip = chipIndex
        if meaningLabel.alpha > 0 {
            UIView.animate(withDuration: 0.2) { self.meaningLabel.alpha = 0 }
        }
        for (offset, chip) in chips.enumerated() {
            chip.setSelected(offset == chipIndex, animated: true)
        }
        let entry = entries[chipIndex]
        underlines?.highlight(entry.tokenIndex)

        let chip = chips[chipIndex]
        DefinitionCalloutPresenter.shared.presentOrUpdate(
            text: entry.piece.gloss,
            surface: entry.piece.japanese,
            lineFragments: [chip.bounds],
            in: chip
        ) { [weak self] _ in
            // The full dictionary sheet can call the gateway; the scripted breakdown can't.
            guard let self, let script = ListenFirstContent.breakdowns[self.line.japanese] else { return }
            self.closeDefinition()
            self.presentBreakdown(of: TutorLine(self.line.japanese, self.line.english), script: script)
        }

        hanaStage?.look(atWindowPoint: chip.convert(CGPoint(x: chip.bounds.midX, y: chip.bounds.midY), to: nil))
    }

    private func closeDefinition() {
        selectedChip = nil
        chips.forEach { $0.setSelected(false, animated: true) }
        underlines?.highlight(nil)
        DefinitionCalloutPresenter.shared.dismiss(animated: true)
    }

    @objc private func lineTapped() {
        guard lineView?.isRevealed == true else { return }
        HapticsHelper.lightHaptic()
        closeDefinition()
        stopPlayback()
        voice.play(ListenFirstContent.lineClip(at: ListenFirstContent.takeApartLine))
    }

    private func stopPlayback() {
        voice.stop()
        meters.stop()
    }
}

// MARK: - Underlines

/// Draws one underline per word under a revealed line's Japanese, measured by the label
/// itself so furigana and wrapping are accounted for.
final class ListenFirstTokenUnderlines {

    private weak var label: FuriganaTranscriptLabel?
    private let tokens: [String]
    private var lines: [CAShapeLayer] = []

    private static let gap: CGFloat = 3
    private static let color = UIColor.tertiaryLabel

    init(label: FuriganaTranscriptLabel, tokens: [String]) {
        self.label = label
        self.tokens = tokens
    }

    /// Each token's range in the label's current text, aligned with `tokens` (nil if not found).
    /// Searched in order, so a repeated token (like の) maps to the right spot. The bubble
    /// glues characters with invisible word joiners to control wrapping (ま⁠だ), so those
    /// are skipped while matching and the ranges map back onto the real string.
    var ranges: [NSRange?] {
        guard let string = label?.attributedText?.string else { return tokens.map { _ in nil } }
        let invisible: Set<UInt16> = [0x2060, 0x200B, 0xFEFF]
        var visible: [UInt16] = []
        var original: [Int] = []
        for (offset, unit) in string.utf16.enumerated() where !invisible.contains(unit) {
            visible.append(unit)
            original.append(offset)
        }
        let haystack = String(utf16CodeUnits: visible, count: visible.count) as NSString
        var cursor = 0
        return tokens.map { token in
            let found = haystack.range(of: token, range: NSRange(location: cursor, length: haystack.length - cursor))
            guard found.location != NSNotFound, found.length > 0 else { return nil }
            cursor = NSMaxRange(found)
            let start = original[found.location]
            let end = original[NSMaxRange(found) - 1] + 1
            return NSRange(location: start, length: end - start)
        }
    }

    /// Draws left to right. Returns how long the whole pass takes.
    @discardableResult
    func draw(animated: Bool) -> TimeInterval {
        guard let label else { return 0 }
        lines.forEach { $0.removeFromSuperlayer() }
        label.superview?.layoutIfNeeded()
        let stagger = 0.1, duration = 0.3
        let color = Self.color.resolvedColor(with: label.traitCollection).cgColor
        lines = ranges.compactMap { $0 }.enumerated().map { index, range in
            let line = CAShapeLayer()
            line.path = Self.path(for: range, in: label)
            line.strokeColor = color
            line.lineWidth = 2.5
            line.lineCap = .round
            line.fillColor = nil
            label.layer.addSublayer(line)
            if animated {
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0
                draw.toValue = 1
                draw.duration = duration
                draw.beginTime = CACurrentMediaTime() + Double(index) * stagger
                draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
                draw.fillMode = .backwards
                line.add(draw, forKey: "draw")
            }
            return line
        }
        return animated ? Double(max(0, lines.count - 1)) * stagger + duration : 0
    }

    /// Re-measures the drawn underlines without animating.
    func relayout() {
        guard let label, !lines.isEmpty else { return }
        let found = ranges.compactMap { $0 }
        guard found.count == lines.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (line, range) in zip(lines, found) {
            line.path = Self.path(for: range, in: label)
        }
        CATransaction.commit()
    }

    private static func path(for range: NSRange, in label: FuriganaTranscriptLabel) -> CGPath {
        let path = UIBezierPath()
        for segment in label.baseTextSegments(for: range) {
            let y = segment.baselineY + 5
            path.move(to: CGPoint(x: segment.rect.minX + gap / 2, y: y))
            path.addLine(to: CGPoint(x: segment.rect.maxX - gap / 2, y: y))
        }
        return path.cgPath
    }

    /// Center of a token's first segment, in window coordinates; where its chip flies from.
    func tokenCenterInWindow(_ index: Int) -> CGPoint? {
        let ranges = ranges
        guard let label, ranges.indices.contains(index), let range = ranges[index],
              let rect = label.baseTextSegments(for: range).first?.rect else { return nil }
        return label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
    }

    /// Paints the label's own token marker behind one word (nil clears it).
    func highlight(_ index: Int?) {
        guard let label else { return }
        let ranges = ranges
        let range = index.flatMap { ranges.indices.contains($0) ? ranges[$0] : nil } ?? nil
        label.setTokenHighlightPreservingLayout(
            foregroundColor: .label,
            highlightedRange: range,
            fullHeight: false
        )
    }
}

// MARK: - Chip

/// One word, pulled out of the line. Tapping it selects it.
final class ListenFirstTokenChip: UIControl {

    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .button

        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (chip: ListenFirstTokenChip, _) in
            chip.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        UIView.animate(withDuration: animated ? 0.2 : 0) {
            self.applyChrome()
        }
    }

    private func applyChrome() {
        backgroundColor = isSelected ? UIColor.systemYellow.withAlphaComponent(0.22) : ExperimentPalette.cardSurface
        layer.borderColor = (isSelected ? UIColor.systemYellow : ExperimentPalette.cardBorder).cgColor
    }
}
