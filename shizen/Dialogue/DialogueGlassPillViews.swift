//
//  DialogueGlassPillViews.swift
//  shizen
//
//  Glass-backed pills and wrapping flow layout for dialogue learning highlights.
//

import InteractionKit
import UIKit

enum DialogueGlassPillStyle {
    case vocab
    case grammar
}

// MARK: - Pill

final class DialogueGlassPillView: UIView {

    private static let cornerRadius: CGFloat = 18
    private static let contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16)
    private static let pillFont = UIFont.systemFont(ofSize: 18, weight: .regular)
    private static let fixedBandHeight = JapaneseFuriganaBuilder.dialoguePillFixedBandHeight(for: pillFont)
    static let fixedPillHeight = contentInsets.top + fixedBandHeight + contentInsets.bottom

    private enum ControlTappedState {
        case touchDown
        case touchCancel
        case touchUp
    }

    private let style: DialogueGlassPillStyle
    private let glassView: UIVisualEffectView
    private let titleLabel = FuriganaTranscriptLabel()
    private var titleTopConstraint: NSLayoutConstraint!

    /// Raw text this pill represents, forwarded to the tap handler.
    let text: String
    /// Invoked when the pill is tapped, with the pill's text.
    var onTap: ((String) -> Void)?

    // Press feedback adapted from `PrimaryButton` (single haptic on press-down).
    private let pressHaptic = UISelectionFeedbackGenerator()
    /// Tint overlaid on the glass while pressed.
    private let pressTintView = UIView()

    init(text: String, style: DialogueGlassPillStyle = .vocab) {
        self.style = style
        self.text = text
        glassView = LiquidGlassEffectView.makeLightPillContainer()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = text

        LiquidGlassEffectView.applyPillStyle(to: glassView, cornerRadius: Self.cornerRadius)

        pressTintView.translatesAutoresizingMaskIntoConstraints = false
        pressTintView.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        pressTintView.layer.cornerRadius = Self.cornerRadius
        pressTintView.layer.cornerCurve = .continuous
        pressTintView.isUserInteractionEnabled = false
        pressTintView.alpha = 0

        titleLabel.clipsToBounds = false
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassView)
        addSubview(pressTintView)
        addSubview(titleLabel)

        titleTopConstraint = titleLabel.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Self.contentInsets.top
        )

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pressTintView.topAnchor.constraint(equalTo: topAnchor),
            pressTintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pressTintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pressTintView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleTopConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentInsets.left),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInsets.right),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Self.contentInsets.bottom),
            heightAnchor.constraint(equalToConstant: Self.fixedPillHeight),
        ])

        applyText(text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyText(_ text: String) {
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: titleLabel,
            attributed: JapaneseFuriganaBuilder.scenarioAttributedString(
                for: text,
                font: Self.pillFont,
                textColor: .label
            ),
            contentInsets: JapaneseFuriganaBuilder.dialoguePillDisplayInsets(
                for: Self.pillFont,
                text: text,
                style: style
            )
        )
        titleTopConstraint.constant = Self.contentInsets.top
            + JapaneseFuriganaBuilder.dialoguePillLabelBandTopOffset(
                for: Self.pillFont,
                text: text,
                style: style
            )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pressHaptic.prepare()
    }

    // Touch tracking + press animation adapted from `PrimaryButton`: scale down
    // and tint on touch-down with a single soft haptic; restore on
    // touch-up/cancel; fire `onTap` only when the touch ends inside.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        pressHaptic.selectionChanged()
        standardControlAnimation(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let endedInside = touches.first.map { bounds.contains($0.location(in: self)) } ?? false
        if endedInside {
            standardControlAnimation(.touchUp)
            onTap?(text)
        } else {
            standardControlAnimation(.touchCancel)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        standardControlAnimation(.touchCancel)
    }

    private func standardControlAnimation(_ tappedState: ControlTappedState) {
        switch tappedState {
        case .touchDown:
            UIView.animate(withDuration: 0.075, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                self.pressTintView.alpha = 1
            }
        case .touchCancel, .touchUp:
            UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = .identity
                self.pressTintView.alpha = 0
            }
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let horizontalPadding = Self.contentInsets.left + Self.contentInsets.right
        let maxLabelWidth = max(0, size.width - horizontalPadding)
        let labelSize = titleLabel.sizeThatFits(
            CGSize(width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(
            width: labelSize.width + horizontalPadding,
            height: Self.fixedPillHeight
        )
    }
}

// MARK: - Interactive glass chip

/// Glass-backed, tappable chip matching `DialogueGlassPillView`'s surface, with
/// touch-down / touch-up scale + dim animations. Stacks a primary line over an
/// optional caption (e.g. a kanji glyph above its brief meaning).
final class GlassChipControl: UIControl {

    private static let cornerRadius: CGFloat = 14
    private static let contentInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    private let glassView: UIVisualEffectView
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()

    init(title: String, subtitle: String?, titleFont: UIFont, subtitleFont: UIFont) {
        glassView = LiquidGlassEffectView.makeLightPillContainer()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")

        LiquidGlassEffectView.applyPillStyle(to: glassView, cornerRadius: Self.cornerRadius)
        glassView.isUserInteractionEnabled = false

        titleLabel.text = title
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        subtitleLabel.text = subtitle
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)

        addSubview(glassView)
        addSubview(stack)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentInsets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentInsets.bottom),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentInsets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInsets.right),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Press animation

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            animatePress(down: isHighlighted)
        }
    }

    private func animatePress(down: Bool) {
        UIView.animate(
            withDuration: down ? 0.12 : 0.28,
            delay: 0,
            usingSpringWithDamping: down ? 1 : 0.6,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = down ? CGAffineTransform(scaleX: 0.93, y: 0.93) : .identity
            self.alpha = down ? 0.7 : 1
        }
    }
}

// MARK: - Wrapping flow

final class DialogueGlassPillFlowView: UIView {

    private static let horizontalSpacing: CGFloat = 10
    private static let verticalSpacing: CGFloat = 10

    private var pillViews: [DialogueGlassPillView] = []
    private var laidOutHeight: CGFloat = 0
    private var pillStyle: DialogueGlassPillStyle = .vocab

    /// Forwarded to each pill; invoked with the tapped pill's text.
    var onPillTap: ((String) -> Void)?
    /// Invoked with grammar point id when a tagged grammar pill is tapped.
    var onGrammarTap: ((String) -> Void)?

    func configure(texts: [String], style: DialogueGlassPillStyle = .vocab) {
        pillStyle = style
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = texts.map { text in
            let pill = DialogueGlassPillView(text: text, style: style)
            pill.onTap = { [weak self] tapped in self?.onPillTap?(tapped) }
            addSubview(pill)
            return pill
        }
        laidOutHeight = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func configureGrammar(patterns: [DialogueGrammarPatternRef], style: DialogueGlassPillStyle = .grammar) {
        pillStyle = style
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = patterns.map { pattern in
            let pill = DialogueGlassPillView(text: pattern.label, style: style)
            if let grammarPointID = pattern.grammarPointID {
                pill.onTap = { [weak self] _ in self?.onGrammarTap?(grammarPointID) }
            }
            addSubview(pill)
            return pill
        }
        laidOutHeight = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = resolvedLayoutWidth()
        guard width > 0 else { return }

        let height = layoutPills(in: width)
        if abs(height - laidOutHeight) > 0.5 {
            laidOutHeight = height
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = resolvedLayoutWidth()
        guard width > 0, !pillViews.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        let height = laidOutHeight > 0 ? laidOutHeight : measuredHeight(for: width)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width > 0 ? size.width : resolvedLayoutWidth()
        return CGSize(width: width, height: measuredHeight(for: width))
    }

    private func resolvedLayoutWidth() -> CGFloat {
        if bounds.width > 0 { return bounds.width }
        var view: UIView? = superview
        while let candidate = view {
            if candidate.bounds.width > 0 { return candidate.bounds.width }
            view = candidate.superview
        }
        return 0
    }

    @discardableResult
    private func layoutPills(in width: CGFloat) -> CGFloat {
        guard width > 0, !pillViews.isEmpty else { return 0 }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for pill in pillViews {
            let pillSize = pill.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            let fitsOnRow = x == 0 || x + pillSize.width <= width + 0.5
            if !fitsOnRow {
                x = 0
                y += rowHeight + Self.verticalSpacing
                rowHeight = 0
            }

            pill.frame = CGRect(x: x, y: y, width: pillSize.width, height: DialogueGlassPillView.fixedPillHeight)
            x += pillSize.width + Self.horizontalSpacing
            rowHeight = max(rowHeight, DialogueGlassPillView.fixedPillHeight)
        }

        return y + rowHeight
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0, !pillViews.isEmpty else { return 0 }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for pill in pillViews {
            let pillSize = pill.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            let fitsOnRow = x == 0 || x + pillSize.width <= width + 0.5
            if !fitsOnRow {
                x = 0
                y += rowHeight + Self.verticalSpacing
                rowHeight = 0
            }
            x += pillSize.width + Self.horizontalSpacing
            rowHeight = max(rowHeight, DialogueGlassPillView.fixedPillHeight)
        }

        return y + rowHeight
    }
}

// MARK: - Section

final class DialogueLearningHighlightsSectionView: UIView {

    private let titleLabel = UILabel()
    private let flowView = DialogueGlassPillFlowView()
    private let pillStyle: DialogueGlassPillStyle

    /// Forwarded to each pill; invoked with the tapped pill's text.
    var onPillTap: ((String) -> Void)? {
        didSet { flowView.onPillTap = onPillTap }
    }

    var onGrammarTap: ((String) -> Void)? {
        didSet { flowView.onGrammarTap = onGrammarTap }
    }

    init(pillStyle: DialogueGlassPillStyle) {
        self.pillStyle = pillStyle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        flowView.translatesAutoresizingMaskIntoConstraints = false
        flowView.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [titleLabel, flowView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, items: [String]) {
        titleLabel.text = title
        flowView.configure(texts: items, style: pillStyle)
        isHidden = items.isEmpty
        setNeedsLayout()
    }

    func configureGrammar(title: String, patterns: [DialogueGrammarPatternRef]) {
        titleLabel.text = title
        flowView.configureGrammar(patterns: patterns, style: pillStyle)
        isHidden = patterns.isEmpty
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        flowView.setNeedsLayout()
    }
}

// MARK: - Notes section

final class DialogueLearningContextNotesView: UIView {

    private let titleLabel = UILabel()
    private let notesStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.text = "NOTES"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        notesStack.axis = .vertical
        notesStack.alignment = .fill
        notesStack.spacing = 12
        notesStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, notesStack])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(notes: [String]) {
        notesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for note in notes {
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .label
            label.numberOfLines = 0
            label.text = note
            notesStack.addArrangedSubview(label)
        }

        isHidden = notes.isEmpty
    }
}

// MARK: - Page content

final class DialogueLearningHighlightsContentView: UIView {

    private let vocabSection = DialogueLearningHighlightsSectionView(pillStyle: .vocab)
    private let grammarSection = DialogueLearningHighlightsSectionView(pillStyle: .grammar)
    private let notesSection = DialogueLearningContextNotesView()
    private let contentStack = UIStackView()

    /// Invoked with the tapped vocabulary word, for dictionary lookup.
    var onSelectVocabulary: ((String) -> Void)? {
        didSet { vocabSection.onPillTap = onSelectVocabulary }
    }

    /// Invoked with a grammar point id when a tagged grammar pill is tapped.
    var onSelectGrammar: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(vocabSection)
        contentStack.addArrangedSubview(grammarSection)
        contentStack.addArrangedSubview(notesSection)

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(highlights: DialogueLearningHighlights) {
        vocabSection.configure(title: "VOCAB", items: highlights.vocabulary)
        grammarSection.configureGrammar(title: "GRAMMAR", patterns: highlights.grammarPatterns)
        grammarSection.onGrammarTap = onSelectGrammar
        notesSection.configure(notes: highlights.contextNotes)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 {
            vocabSection.setNeedsLayout()
            grammarSection.setNeedsLayout()
        }
    }
}
