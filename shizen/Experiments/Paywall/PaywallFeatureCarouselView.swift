//
//  PaywallFeatureCarouselView.swift
//  shizen
//
//  Swipeable glass feature cards with a page control. Each card shows a small preview of
//  the feature (lesson thumbnails, a casual line in the lesson glass bubble, a word
//  insight, a quiz, a saved flashcard), all from one train-station scene so they read as
//  one story. Cards auto-advance until the user swipes or taps the page control.
//

import UIKit

final class PaywallFeatureCarouselView: UIView {
    /// Fill for the small shapes inside a preview.
    private static let chip = UIColor.label.withAlphaComponent(0.06)
    private static let previewHeight: CGFloat = 170
    /// Same weight as the lesson bubbles, sized down for the preview.
    private static let bubbleFont = UIFont.systemFont(ofSize: 18, weight: .medium)
    private static let cardGap: CGFloat = 12
    /// Padding between the glass card edge and everything inside it.
    private static let cardInset: CGFloat = 18
    private static let autoAdvanceInterval: TimeInterval = 4

    /// What moved the carousel to a new page.
    enum PageChangeTrigger: String {
        case auto
        case swipe
        case pageControl = "page_control"
    }

    /// Called when a new page settles, from a swipe, a tap, or auto-advance.
    var onPageChange: ((Int, PageChangeTrigger) -> Void)?

    private let carousel = UIScrollView()
    private let pageControl = UIPageControl()
    private var autoAdvance: Timer?
    private var currentPage = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        let cards = makeCarousel()

        pageControl.numberOfPages = PaywallCopy.features.count
        pageControl.currentPageIndicatorTintColor = .label
        pageControl.pageIndicatorTintColor = UIColor.label.withAlphaComponent(0.2)
        pageControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            stopAutoAdvance()
            scroll(to: pageControl.currentPage, animated: true, trigger: .pageControl)
        }, for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [cards, pageControl])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Carousel

    /// Paging scroll view one card + gap wide, so each page lands a card flush with the
    /// content edges and the neighbors peek into the side margins.
    private func makeCarousel() -> UIView {
        let cards = PaywallCopy.features.map(makeCard)
        let row = UIStackView(arrangedSubviews: cards)
        row.spacing = Self.cardGap
        row.alignment = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        carousel.isPagingEnabled = true
        carousel.clipsToBounds = false
        carousel.showsHorizontalScrollIndicator = false
        carousel.alwaysBounceVertical = false
        carousel.delegate = self
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.addSubview(row)

        let container = UIView()
        container.addSubview(carousel)
        NSLayoutConstraint.activate([
            carousel.topAnchor.constraint(equalTo: container.topAnchor),
            carousel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            carousel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            carousel.widthAnchor.constraint(equalTo: container.widthAnchor, constant: Self.cardGap),

            row.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor),
            // A trailing gap makes the content an exact multiple of the page width.
            row.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor, constant: -Self.cardGap),
            // No vertical scrolling: the carousel is as tall as its tallest card.
            carousel.frameLayoutGuide.heightAnchor.constraint(equalTo: carousel.contentLayoutGuide.heightAnchor),
        ])
        for card in cards {
            card.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
        return container
    }

    private func makeCard(_ feature: PaywallCopy.Feature) -> UIView {
        let preview = makePreview(for: feature)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: Self.previewHeight).isActive = true

        let icon = UIImageView(image: UIImage(systemName: feature.symbol))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.tintColor = feature.tint
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = feature.title
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.numberOfLines = 0
        let heading = UIStackView(arrangedSubviews: [icon, title])
        heading.spacing = 8
        heading.alignment = .center

        let detail = UILabel()
        detail.text = feature.detail
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [heading, detail])
        text.axis = .vertical
        text.spacing = 4
        text.isLayoutMarginsRelativeArrangement = true
        text.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)

        let stack = UIStackView(arrangedSubviews: [preview, text])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glass.cornerConfiguration = .corners(radius: .fixed(28))
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: Self.cardInset),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: Self.cardInset),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -Self.cardInset),
            // Shorter cards stretch to the tallest; their text stays top-aligned.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: glass.contentView.bottomAnchor, constant: -(Self.cardInset + 4)),
        ])
        let hug = glass.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeLevel
        hug.isActive = true

        glass.isAccessibilityElement = true
        glass.accessibilityLabel = "\(feature.title). \(feature.detail)"
        return glass
    }

    private func scroll(to page: Int, animated: Bool, trigger: PageChangeTrigger) {
        let width = carousel.bounds.width
        guard width > 0 else { return }
        carousel.setContentOffset(CGPoint(x: CGFloat(page) * width, y: 0), animated: animated)
        pageDidChange(to: page, trigger: trigger)
    }

    private func pageDidChange(to page: Int, trigger: PageChangeTrigger) {
        guard page != currentPage else { return }
        currentPage = page
        pageControl.currentPage = page
        onPageChange?(page, trigger)
    }

    func startAutoAdvance() {
        guard autoAdvance == nil, !UIAccessibility.isReduceMotionEnabled else { return }
        autoAdvance = Timer.scheduledTimer(withTimeInterval: Self.autoAdvanceInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            scroll(to: (currentPage + 1) % PaywallCopy.features.count, animated: true, trigger: .auto)
        }
    }

    func stopAutoAdvance() {
        autoAdvance?.invalidate()
        autoAdvance = nil
    }

    // MARK: Previews

    private func makePreview(for feature: PaywallCopy.Feature) -> UIView {
        let preview: UIView
        switch feature.kind {
        case .lessons: preview = makeLessonsPreview()
        case .dialogue: preview = makeDialoguePreview()
        case .insights: preview = makeInsightsPreview()
        case .quizzes: preview = makeQuizPreview()
        case .flashcards: preview = makeFlashcardPreview()
        }
        // The lesson art fills its own frame; everything else sits on a soft tint.
        if feature.kind != .lessons {
            preview.backgroundColor = feature.tint.withAlphaComponent(0.12)
        }
        // Roughly concentric with the card's 28pt corners at this inset.
        preview.layer.cornerRadius = 14
        preview.layer.cornerCurve = .continuous
        // The thumbnails round their own corners (clipping here would cut their borders),
        // and the flashcard shadows need to spill past the cards.
        preview.clipsToBounds = feature.kind != .lessons && feature.kind != .flashcards
        return preview
    }

    /// 2×2 grid of bundled lesson thumbnails with an audio-length pill.
    private func makeLessonsPreview() -> UIView {
        let thumbnails = ListenFirstContent.sceneThumbnails.map { name -> UIView in
            let image = UIImageView(image: LessonThumbnailLoader.bundledImage(named: name, targetPixelSize: 480, variant: .color))
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.backgroundColor = Self.chip
            image.layer.cornerRadius = 12
            image.layer.cornerCurve = .continuous
            // A thin light rim lifts the art off the glass.
            image.layer.borderWidth = 1.5
            image.layer.borderColor = UIColor.white.cgColor
            return image
        }
        func pair(_ views: ArraySlice<UIView>) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: Array(views))
            stack.spacing = 8
            stack.distribution = .fillEqually
            return stack
        }
        let grid = UIStackView(arrangedSubviews: [pair(thumbnails.prefix(2)), pair(thumbnails.dropFirst(2).prefix(2))])
        grid.axis = .vertical
        grid.spacing = 8
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false

        let pill = PaywallBadgeLabel(
            text: "▶︎ 2h+ of audio",
            fill: UIColor.black.withAlphaComponent(0.55),
            textColor: .white,
            font: .systemFont(ofSize: 12, weight: .semibold)
        )
        pill.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        let preview = UIView()
        preview.addSubview(grid)
        preview.addSubview(pill)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: preview.topAnchor),
            grid.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            pill.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 10),
            pill.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -10),
        ])
        return preview
    }

    /// A casual line in the lesson's own glass bubble, with the textbook version it
    /// replaces struck through.
    private func makeDialoguePreview() -> UIView {
        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: label,
            text: "電車、もう行っちゃった…",
            font: Self.bubbleFont,
            textColor: .label
        )
        let bubble = DialogueJapaneseBubbleView(label: label)
        bubble.setBackgroundStyle(.glass)
        bubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let gloss = UILabel()
        gloss.text = "The train already left…"
        gloss.font = .systemFont(ofSize: 13)
        gloss.textColor = .secondaryLabel

        let textbook = UILabel()
        textbook.attributedText = NSAttributedString(string: "Textbook: 電車はもう出発しました。", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.tertiaryLabel,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ])

        let bubbleRow = UIStackView(arrangedSubviews: [bubble, UIView()])
        bubbleRow.alignment = .center
        let column = UIStackView(arrangedSubviews: [bubbleRow, gloss, textbook])
        column.axis = .vertical
        column.spacing = 4
        column.setCustomSpacing(8, after: bubbleRow)
        return makeInsetPreview([column], spacing: 0)
    }

    /// A tapped word with its insight card underneath.
    private func makeInsightsPreview() -> UIView {
        let sentence = UILabel()
        let text = NSMutableAttributedString(string: "電車、もう", attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
        text.append(NSAttributedString(string: "行っちゃった", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.thick.rawValue,
        ]))
        sentence.attributedText = text

        let word = UILabel()
        word.text = "行っちゃった · いっちゃった"
        word.font = .systemFont(ofSize: 14, weight: .semibold)
        let meaning = UILabel()
        meaning.text = "Casual 行ってしまった: it's gone, and that's a shame."
        meaning.font = .systemFont(ofSize: 13)
        meaning.textColor = .secondaryLabel
        meaning.numberOfLines = 2
        let tip = UILabel()
        tip.text = "✦ ちゃう adds regret or \"oops, too late\"."
        tip.font = .systemFont(ofSize: 12, weight: .medium)
        tip.textColor = .systemBlue
        tip.numberOfLines = 2

        let card = UIStackView(arrangedSubviews: [word, meaning, tip])
        card.axis = .vertical
        card.spacing = 4
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous

        return makeInsetPreview([sentence, card], spacing: 10)
    }

    /// A comprehension question with the right answer picked.
    private func makeQuizPreview() -> UIView {
        let question = UILabel()
        question.text = "What happened to the train?"
        question.font = .systemFont(ofSize: 15, weight: .semibold)

        let right = makeQuizOption("It already left", isCorrect: true)
        let wrong = makeQuizOption("It's running late", isCorrect: false)
        return makeInsetPreview([question, right, wrong], spacing: 8)
    }

    private func makeQuizOption(_ text: String, isCorrect: Bool) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: isCorrect ? .semibold : .regular)
        let mark = UIImageView(image: UIImage(systemName: isCorrect ? "checkmark.circle.fill" : "circle"))
        mark.tintColor = isCorrect ? .systemGreen : .tertiaryLabel
        mark.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, mark])
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        row.backgroundColor = .systemBackground
        row.layer.cornerRadius = 12
        row.layer.cornerCurve = .continuous
        row.layer.borderWidth = isCorrect ? 1.5 : 0
        row.layer.borderColor = UIColor.systemGreen.cgColor
        return row
    }

    /// A saved card on top of a fanned stack.
    private func makeFlashcardPreview() -> UIView {
        let preview = UIView()
        let cardSize = CGSize(width: 200, height: 112)
        let cardRadius: CGFloat = 16
        /// Lower cards sit further down the stack, so they get a deeper, softer shadow.
        func card(depth: CGFloat) -> UIView {
            let view = UIView()
            // Same surface and dark-mode shadow weight as the app's `VocabFlashcardView`.
            view.backgroundColor = ExperimentPalette.cardSurface
            view.layer.cornerRadius = cardRadius
            view.layer.cornerCurve = .continuous
            view.layer.shadowColor = UIColor.black.cgColor
            func applyShadowOpacity(_ view: UIView) {
                let base: Float = view.traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.10
                view.layer.shadowOpacity = base + Float(0.025 * depth)
            }
            applyShadowOpacity(view)
            view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _: UITraitCollection) in
                applyShadowOpacity(view)
            }
            view.layer.shadowRadius = 10 + 2 * depth
            view.layer.shadowOffset = CGSize(width: 0, height: 4 + depth)
            // The cards are a fixed size, so the path never needs updating. Without it the
            // shadow is rendered offscreen from the layer's alpha, which smears under the glass.
            view.layer.shadowPath = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: cardSize),
                cornerRadius: cardRadius
            ).cgPath
            // Smooth edges on the rotated cards.
            view.layer.allowsEdgeAntialiasing = true
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
        let back = card(depth: 2)
        let middle = card(depth: 1)
        let front = card(depth: 0)
        // Nudge the lower cards up so their edges peek out above the front card.
        back.transform = CGAffineTransform(translationX: -6, y: -10).rotated(by: -0.1)
        middle.transform = CGAffineTransform(translationX: 5, y: -5).rotated(by: 0.06)

        let reading = UILabel()
        reading.text = "のりかえ"
        reading.font = .systemFont(ofSize: 12)
        reading.textColor = .secondaryLabel
        let word = UILabel()
        word.text = "乗り換え"
        word.font = .systemFont(ofSize: 26, weight: .bold)
        let meaning = UILabel()
        meaning.text = "transfer (between trains)"
        meaning.font = .systemFont(ofSize: 13)
        meaning.textColor = .secondaryLabel
        let text = UIStackView(arrangedSubviews: [reading, word, meaning])
        text.axis = .vertical
        text.alignment = .center
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        front.addSubview(text)

        let saved = UIImageView(image: UIImage(systemName: "bookmark.fill"))
        saved.tintColor = .systemPurple
        saved.translatesAutoresizingMaskIntoConstraints = false
        front.addSubview(saved)

        for view in [back, middle, front] {
            preview.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: cardSize.width),
                view.heightAnchor.constraint(equalToConstant: cardSize.height),
            ])
        }
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: front.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: front.centerYAnchor),
            saved.topAnchor.constraint(equalTo: front.topAnchor, constant: 10),
            saved.trailingAnchor.constraint(equalTo: front.trailingAnchor, constant: -12),
        ])
        return preview
    }

    /// Vertically centered column with the preview's standard padding.
    private func makeInsetPreview(_ views: [UIView], spacing: CGFloat) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let preview = UIView()
        preview.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(greaterThanOrEqualTo: preview.topAnchor, constant: 14),
        ])
        return preview
    }
}

extension PaywallFeatureCarouselView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        stopAutoAdvance()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        pageDidChange(to: Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded()), trigger: .swipe)
    }
}
