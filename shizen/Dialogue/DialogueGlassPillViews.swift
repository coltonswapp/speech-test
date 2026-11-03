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
    /// True after the learner has opened this pill (dictionary / grammar).
    private(set) var isViewed = false

    // Press feedback adapted from `PrimaryButton` (single haptic on press-down).
    private let pressHaptic = UISelectionFeedbackGenerator()
    /// Tint overlaid on the glass while pressed.
    private let pressTintView = UIView()
    /// Fallback fill for the viewed state on OS versions without glass tint.
    private let viewedTintView = UIView()

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

        viewedTintView.translatesAutoresizingMaskIntoConstraints = false
        viewedTintView.backgroundColor = UIColor.systemGray.withAlphaComponent(0.22)
        viewedTintView.layer.cornerRadius = Self.cornerRadius
        viewedTintView.layer.cornerCurve = .continuous
        viewedTintView.isUserInteractionEnabled = false
        viewedTintView.alpha = 0

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
        addSubview(viewedTintView)
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

            viewedTintView.topAnchor.constraint(equalTo: topAnchor),
            viewedTintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            viewedTintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewedTintView.bottomAnchor.constraint(equalTo: bottomAnchor),

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

    func setViewed(_ viewed: Bool, animated: Bool) {
        guard isViewed != viewed else { return }
        isViewed = viewed
        accessibilityValue = viewed ? "Looked up" : nil
        applyViewedAppearance(animated: animated)
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

    private func applyViewedAppearance(animated: Bool) {
        applyGlassTint(viewed: isViewed)

        let borderColor = isViewed
            ? UIColor.systemGray.withAlphaComponent(0.38).cgColor
            : UIColor.white.withAlphaComponent(0.22).cgColor
        let overlayAlpha: CGFloat
        if #available(iOS 26.0, *) {
            overlayAlpha = 0
        } else {
            overlayAlpha = isViewed ? 1 : 0
        }

        let updates = { [self] in
            glassView.layer.borderColor = borderColor
            viewedTintView.alpha = overlayAlpha
        }

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func applyGlassTint(viewed: Bool) {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = false
            if viewed {
                glassEffect.tintColor = UIColor.systemGray3.withAlphaComponent(0.55)
            }
            glassView.effect = glassEffect
        } else {
            glassView.backgroundColor = viewed
                ? UIColor.systemGray5
                : UIColor.systemBackground.withAlphaComponent(0.82)
        }
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

    override var intrinsicContentSize: CGSize {
        sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: Self.fixedPillHeight))
    }
}

// MARK: - Interactive glass chip

/// Glass-backed, tappable chip matching `DialogueGlassPillView`'s surface, with
/// touch-down / touch-up scale + dim animations. Stacks a primary line over an
/// optional caption (e.g. a kanji glyph above its brief meaning).
final class GlassChipControl: UIControl {

    private static let cornerRadius: CGFloat = 14
    private static let contentInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    /// The label already reserves the ruby above the glyphs. Leaving the full
    /// top pad on top of that leaves a void above the reading.
    private static let furiganaUpwardOffset: CGFloat = 10

    private let glassView: UIVisualEffectView
    private let titleLabel: UILabel
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()

    init(
        title: String,
        subtitle: String?,
        titleFont: UIFont,
        subtitleFont: UIFont,
        showsFurigana: Bool = false,
        contentAlignment: NSTextAlignment = .center
    ) {
        glassView = LiquidGlassEffectView.makeLightPillContainer()
        titleLabel = showsFurigana ? FuriganaTranscriptLabel() : UILabel()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")

        LiquidGlassEffectView.applyPillStyle(to: glassView, cornerRadius: Self.cornerRadius)
        glassView.isUserInteractionEnabled = false

        clipsToBounds = false
        if showsFurigana, let furigana = titleLabel as? FuriganaTranscriptLabel {
            furigana.numberOfLines = 2
            furigana.clipsToBounds = false
            // Keep the ruby inside the chip. The default alignment rect lets it
            // paint above the glass, where the card clips it.
            furigana.verticalTextInsetsAffectAlignmentRect = false
            JapaneseFuriganaBuilder.applyScrubDisplay(
                to: furigana,
                attributed: JapaneseFuriganaBuilder.attributedString(
                    for: title,
                    font: titleFont,
                    textColor: .label
                ),
                contentInsets: UIEdgeInsets(
                    top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: titleFont),
                    left: 0,
                    bottom: 0,
                    right: 0
                )
            )
        } else {
            titleLabel.text = title
            titleLabel.font = titleFont
            titleLabel.textColor = .label
        }
        titleLabel.textAlignment = contentAlignment

        subtitleLabel.text = subtitle
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = contentAlignment
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)

        stack.axis = .vertical
        stack.alignment = contentAlignment == .center ? .center : .leading
        stack.spacing = 2
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

            stack.topAnchor.constraint(
                equalTo: topAnchor,
                constant: showsFurigana
                    ? Self.contentInsets.top - Self.furiganaUpwardOffset
                    : Self.contentInsets.top
            ),
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

// MARK: - Toggle tag

/// Glass pill matching `DialogueGlassPillView`'s surface that toggles on tap.
/// Selected tags tint blue with a semibold label; width is measured at semibold
/// so toggling never reflows the row.
final class GlassTagControl: UIControl {

    private static let cornerRadius: CGFloat = 18
    private static let contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    private static let regularFont = UIFontMetrics(forTextStyle: .body)
        .scaledFont(for: .systemFont(ofSize: 17, weight: .regular))
    private static let selectedFont = UIFontMetrics(forTextStyle: .body)
        .scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
    static var fixedHeight: CGFloat {
        ceil(selectedFont.lineHeight) + contentInsets.top + contentInsets.bottom
    }

    private let glassView: UIVisualEffectView
    /// Fallback fill for the selected state on OS versions without glass tint.
    private let selectedFillView = UIView()
    private let titleLabel = UILabel()
    private let selectionHaptic = UISelectionFeedbackGenerator()

    init(title: String) {
        glassView = LiquidGlassEffectView.makeLightPillContainer()
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title

        LiquidGlassEffectView.applyPillStyle(to: glassView, cornerRadius: Self.cornerRadius)
        glassView.isUserInteractionEnabled = false

        selectedFillView.translatesAutoresizingMaskIntoConstraints = false
        selectedFillView.backgroundColor = .systemBlue
        selectedFillView.layer.cornerRadius = Self.cornerRadius
        selectedFillView.layer.cornerCurve = .continuous
        selectedFillView.isUserInteractionEnabled = false
        selectedFillView.alpha = 0

        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassView)
        addSubview(selectedFillView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            selectedFillView.topAnchor.constraint(equalTo: topAnchor),
            selectedFillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectedFillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectedFillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTarget(self, action: #selector(toggleSelected), for: .touchUpInside)
        applySelectionAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            applySelectionAppearance(animated: true)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            animatePress(down: isHighlighted)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        selectionHaptic.prepare()
    }

    @objc private func toggleSelected() {
        isSelected.toggle()
        selectionHaptic.selectionChanged()
        sendActions(for: .valueChanged)
    }

    private func applySelectionAppearance(animated: Bool) {
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        titleLabel.font = isSelected ? Self.selectedFont : Self.regularFont

        let fillAlpha: CGFloat
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = false
            if isSelected {
                glassEffect.tintColor = .systemBlue
            }
            glassView.effect = glassEffect
            fillAlpha = 0
        } else {
            fillAlpha = isSelected ? 1 : 0
        }

        let updates = { [self] in
            selectedFillView.alpha = fillAlpha
            titleLabel.textColor = isSelected ? .white : .label
            glassView.layer.borderColor = isSelected
                ? UIColor.clear.cgColor
                : UIColor.white.withAlphaComponent(0.22).cgColor
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
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
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let titleWidth = ceil(
            (titleLabel.text ?? "").size(withAttributes: [.font: Self.selectedFont]).width
        )
        return CGSize(
            width: titleWidth + Self.contentInsets.left + Self.contentInsets.right,
            height: Self.fixedHeight
        )
    }

    override var intrinsicContentSize: CGSize {
        sizeThatFits(.zero)
    }
}

// MARK: - Wrapping flow

/// Left-aligned wrapping rows shared by the glass pill and tag flows.
enum GlassPillFlowLayout {
    static let horizontalSpacing: CGFloat = 10
    static let verticalSpacing: CGFloat = 10

    static func frames(for sizes: [CGSize], in width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in sizes {
            let fitsOnRow = x == 0 || x + size.width <= width + 0.5
            if !fitsOnRow {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return (frames, sizes.isEmpty ? 0 : y + rowHeight)
    }

    /// Same left-aligned rows as `frames`, but break points are chosen so leftover
    /// space is shared across rows. A row of one pill is used only when nothing else fits.
    static func balancedFrames(for sizes: [CGSize], in width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let count = sizes.count
        guard count > 0, width > 0 else { return ([], 0) }

        func rowWidth(from start: Int, to end: Int) -> CGFloat? {
            var used: CGFloat = 0
            for index in start..<end {
                if index > start { used += horizontalSpacing }
                used += sizes[index].width
                if used > width + 0.5 { return nil }
            }
            return used
        }

        var cost = Array(repeating: CGFloat.greatestFiniteMagnitude, count: count + 1)
        var choice = Array(repeating: 0, count: count + 1)
        cost[0] = 0
        for start in 0..<count {
            guard cost[start].isFinite else { continue }
            for end in (start + 1)...count {
                guard let used = rowWidth(from: start, to: end) else { break }
                let leftover = width - used
                var rowCost = leftover * leftover
                if end - start == 1, count > 1 {
                    rowCost += 80_000
                }
                let total = cost[start] + rowCost
                if total < cost[end] {
                    cost[end] = total
                    choice[end] = start
                }
            }
        }
        guard cost[count].isFinite else { return frames(for: sizes, in: width) }

        var spans: [(start: Int, end: Int)] = []
        var end = count
        while end > 0 {
            let start = choice[end]
            spans.append((start, end))
            end = start
        }

        var frames: [CGRect] = []
        var y: CGFloat = 0
        for (offset, span) in spans.reversed().enumerated() {
            var x: CGFloat = 0
            var rowHeight: CGFloat = 0
            for index in span.start..<span.end {
                let size = sizes[index]
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                x += size.width + horizontalSpacing
                rowHeight = max(rowHeight, size.height)
            }
            let isLast = offset == spans.count - 1
            y += isLast ? rowHeight : rowHeight + verticalSpacing
        }
        return (frames, y)
    }
}

private extension UIView {
    /// Own width, else the nearest ancestor's, so flows can size before their first layout pass.
    var nearestLaidOutWidth: CGFloat {
        var view: UIView? = self
        while let candidate = view {
            if candidate.bounds.width > 0 { return candidate.bounds.width }
            view = candidate.superview
        }
        return 0
    }
}

/// Wraps `GlassTagControl`s into balanced rows so a long label does not leave a pill alone.
final class GlassTagFlowView: UIView {

    private var tagViews: [GlassTagControl] = []
    private var laidOutHeight: CGFloat = 0

    func setTags(_ tags: [GlassTagControl]) {
        tagViews.forEach { $0.removeFromSuperview() }
        tagViews = tags
        tags.forEach { addSubview($0) }
        laidOutHeight = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = nearestLaidOutWidth
        guard width > 0 else { return }

        let layout = flowLayout(in: width)
        zip(tagViews, layout.frames).forEach { $0.frame = $1 }
        if abs(layout.height - laidOutHeight) > 0.5 {
            laidOutHeight = layout.height
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = nearestLaidOutWidth
        guard width > 0, !tagViews.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        let height = laidOutHeight > 0 ? laidOutHeight : flowLayout(in: width).height
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width > 0 ? size.width : nearestLaidOutWidth
        return CGSize(width: width, height: flowLayout(in: width).height)
    }

    private func flowLayout(in width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let sizes = tagViews.map { $0.sizeThatFits(.zero) }
        return GlassPillFlowLayout.balancedFrames(for: sizes, in: width)
    }
}

final class DialogueGlassPillFlowView: UIView {

    private var pillViews: [DialogueGlassPillView] = []
    private var laidOutHeight: CGFloat = 0
    private var pillStyle: DialogueGlassPillStyle = .vocab

    /// Forwarded to each pill; invoked with the tapped pill's text.
    var onPillTap: ((String) -> Void)?
    /// Invoked with the tapped grammar pattern.
    var onGrammarTap: ((DialogueGrammarPatternRef) -> Void)?
    /// Vocabulary surfaces already opened in this session, kept across `configure`.
    private var viewedTexts: Set<String> = []

    func configure(texts: [String], style: DialogueGlassPillStyle = .vocab) {
        pillStyle = style
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = texts.map { text in
            let pill = DialogueGlassPillView(text: text, style: style)
            pill.onTap = { [weak self] tapped in
                self?.markViewed(text: tapped, animated: true)
                self?.onPillTap?(tapped)
            }
            pill.setViewed(viewedTexts.contains(text), animated: false)
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
            pill.onTap = { [weak self] tapped in
                self?.markViewed(text: tapped, animated: true)
                self?.onGrammarTap?(pattern)
            }
            pill.setViewed(viewedTexts.contains(pattern.label), animated: false)
            addSubview(pill)
            return pill
        }
        laidOutHeight = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func markViewed(text: String, animated: Bool) {
        viewedTexts.insert(text)
        pillViews.first { $0.text == text }?.setViewed(true, animated: animated)
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
        nearestLaidOutWidth
    }

    @discardableResult
    private func layoutPills(in width: CGFloat) -> CGFloat {
        guard width > 0, !pillViews.isEmpty else { return 0 }
        let layout = pillLayout(in: width)
        zip(pillViews, layout.frames).forEach { $0.frame = $1 }
        return layout.height
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0, !pillViews.isEmpty else { return 0 }
        return pillLayout(in: width).height
    }

    private func pillLayout(in width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let sizes = pillViews.map { pill in
            CGSize(
                width: pill.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).width,
                height: DialogueGlassPillView.fixedPillHeight
            )
        }
        return GlassPillFlowLayout.frames(for: sizes, in: width)
    }
}

/// Single-row horizontal glass pills (grammar example chips).
final class DialogueGlassPillStripView: UIView {

    var onPillTap: ((String) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var pillViews: [DialogueGlassPillView] = []
    private var viewedTexts: Set<String> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.clipsToBounds = false
        clipsToBounds = false

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: DialogueGlassPillView.fixedPillHeight),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(texts: [String], style: DialogueGlassPillStyle = .grammar) {
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = texts.map { text in
            let pill = DialogueGlassPillView(text: text, style: style)
            pill.onTap = { [weak self] tapped in
                self?.viewedTexts.insert(tapped)
                self?.pillViews.first { $0.text == tapped }?.setViewed(true, animated: true)
                self?.onPillTap?(tapped)
            }
            pill.setViewed(viewedTexts.contains(text), animated: false)
            pill.setContentHuggingPriority(.required, for: .horizontal)
            pill.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(pill)
            return pill
        }
        isHidden = texts.isEmpty
    }
}

/// Horizontal glass examples, same chip as gloss related-words.
final class DialogueGrammarExampleStripView: UIView {

    var onChipTap: ((GeminiGrammarUsage.Example) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let loadingRow = UIStackView()
    private let loadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let loadingLabel = UILabel()
    private let messageLabel = UILabel()
    private var chips: [GlassChipControl] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.clipsToBounds = false
        clipsToBounds = false

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        loadingSpinner.configure(with: .systemYellow)
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingSpinner.widthAnchor.constraint(equalToConstant: 24),
            loadingSpinner.heightAnchor.constraint(equalToConstant: 24),
        ])
        loadingLabel.text = "Finding examples…"
        loadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        loadingLabel.textColor = .secondaryLabel
        loadingRow.axis = .horizontal
        loadingRow.alignment = .center
        loadingRow.spacing = 10
        loadingRow.translatesAutoresizingMaskIntoConstraints = false
        loadingRow.addArrangedSubview(loadingSpinner)
        loadingRow.addArrangedSubview(loadingLabel)
        loadingRow.isHidden = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(loadingRow)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            loadingRow.topAnchor.constraint(equalTo: topAnchor),
            loadingRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            loadingRow.bottomAnchor.constraint(equalTo: bottomAnchor),

            messageLabel.topAnchor.constraint(equalTo: topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLoading() {
        clearChips()
        messageLabel.isHidden = true
        loadingRow.isHidden = false
        loadingSpinner.isHidden = false
        loadingSpinner.reset()
        scrollView.isHidden = true
        invalidateIntrinsicContentSize()
    }

    func apply(_ items: [GeminiGrammarUsage.Example]) {
        loadingRow.isHidden = true
        loadingSpinner.isHidden = true
        messageLabel.isHidden = true
        clearChips()
        let titleFont = Self.exampleTitleFont
        let subtitleFont = Self.exampleSubtitleFont
        chips = items.map { item in
            let english = item.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let chip = GlassChipControl(
                title: item.japanese,
                subtitle: english.isEmpty ? nil : english,
                titleFont: titleFont,
                subtitleFont: subtitleFont,
                showsFurigana: true,
                contentAlignment: .left
            )
            chip.setContentHuggingPriority(.required, for: .horizontal)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.accessibilityHint = "Opens this example sentence"
            chip.addAction(UIAction { [weak self] _ in
                self?.onChipTap?(item)
            }, for: .touchUpInside)
            stack.addArrangedSubview(chip)
            return chip
        }
        scrollView.isHidden = items.isEmpty
        invalidateIntrinsicContentSize()
    }

    func applyMessage(_ text: String) {
        clearChips()
        loadingRow.isHidden = true
        loadingSpinner.isHidden = true
        scrollView.isHidden = true
        messageLabel.text = text
        messageLabel.isHidden = text.isEmpty
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        if !loadingRow.isHidden {
            return CGSize(width: UIView.noIntrinsicMetric, height: 44)
        }
        if !messageLabel.isHidden {
            let width = bounds.width > 0 ? bounds.width : 320
            let height = messageLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            return CGSize(width: UIView.noIntrinsicMetric, height: max(22, height))
        }
        let chipHeight = chips
            .map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height }
            .max() ?? 0
        return CGSize(width: UIView.noIntrinsicMetric, height: chipHeight)
    }

    /// A step up from body / caption so a short phrase is easier to read in the chip.
    private static var exampleTitleFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static var exampleSubtitleFont: UIFont {
        UIFont.preferredFont(forTextStyle: .footnote)
    }

    private func clearChips() {
        chips.forEach { $0.removeFromSuperview() }
        chips = []
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

    var onGrammarTap: ((DialogueGrammarPatternRef) -> Void)? {
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

    /// Invoked with the tapped grammar pattern, for its detail screen.
    var onSelectGrammar: ((DialogueGrammarPatternRef) -> Void)? {
        didSet { grammarSection.onGrammarTap = onSelectGrammar }
    }

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

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
