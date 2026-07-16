//
//  GrammarExampleScenarioView.swift
//  shizen
//
//  Swipeable dialogue preview card for a grammar example scenario.
//

import UIKit

final class GrammarExampleScenarioView: UIView, UIScrollViewDelegate {

    var onListenTapped: (() -> Void)?

    private struct DialoguePage {
        let japanese: String
    }

    private let cardContainer = UIView()
    private let cardSurface = UIView()
    private let headerLabel = UILabel()
    private let scrollView = UIScrollView()
    private let pagesStack = UIStackView()
    private let pageControl = UIPageControl()
    private let listenButton = UIButton(type: .system)

    private var pages: [DialoguePage] = []
    private var activePageIndex = 0
    private let pageChangeHaptic = UISelectionFeedbackGenerator()

    private static let cardCornerRadius: CGFloat = 14
    private static let cardShadowBleed: CGFloat = 10
    private static let totalHeight: CGFloat = 220
    private static let horizontalInset: CGFloat = 14
    private static let labelMaxWidth: CGFloat = 250
    private static let labelSideInset: CGFloat = 40
    private static let headerTopInset: CGFloat = 12
    private static let footerBottomInset: CGFloat = 10
    private static let dialogueJapaneseFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title1)
        return .systemFont(ofSize: base.pointSize, weight: .semibold)
    }()
    private static let listenButtonHeight: CGFloat = 32

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configure(scenario: GrammarScenario, example: GrammarExample, onListenTapped: (() -> Void)? = nil) {
        self.onListenTapped = onListenTapped
        pages = Self.makePages(scenario: scenario, example: example)
        rebuildPages()
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        activePageIndex = 0
        scrollView.setContentOffset(.zero, animated: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pageChangeHaptic.prepare()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardContainer.layer.shadowPath = UIBezierPath(
            roundedRect: cardContainer.bounds,
            cornerRadius: Self.cardCornerRadius
        ).cgPath
        syncPageControlFromScrollOffset()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyCardShadow()
    }

    // MARK: - Setup

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.clipsToBounds = false
        addSubview(cardContainer)

        cardSurface.translatesAutoresizingMaskIntoConstraints = false
        cardSurface.backgroundColor = ExperimentPalette.cardSurface
        cardSurface.layer.cornerRadius = Self.cardCornerRadius
        cardSurface.layer.cornerCurve = .continuous
        cardSurface.clipsToBounds = true
        cardContainer.addSubview(cardSurface)
        applyCardShadow()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = pages.count > 1
        scrollView.alwaysBounceHorizontal = false
        scrollView.isPagingEnabled = true
        scrollView.delegate = self
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .clear
        cardSurface.addSubview(scrollView)

        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        pagesStack.axis = .vertical
        pagesStack.alignment = .fill
        pagesStack.distribution = .fill
        pagesStack.spacing = 0
        scrollView.addSubview(pagesStack)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .preferredFont(forTextStyle: .caption2)
        headerLabel.textColor = .secondaryLabel
        headerLabel.text = "DIALOGUE"
        headerLabel.isUserInteractionEnabled = false
        cardSurface.addSubview(headerLabel)

        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.hidesForSinglePage = true
        pageControl.isUserInteractionEnabled = true
        pageControl.currentPageIndicatorTintColor = .label
        pageControl.pageIndicatorTintColor = .tertiaryLabel
        pageControl.transform = CGAffineTransform(rotationAngle: .pi / 2)
        pageControl.addTarget(self, action: #selector(pageControlChanged(_:)), for: .valueChanged)

        configureListenButton()
        listenButton.addAction(UIAction { [weak self] _ in self?.onListenTapped?() }, for: .primaryActionTriggered)
        cardSurface.addSubview(pageControl)
        cardSurface.addSubview(listenButton)

        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: topAnchor),
            cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardContainer.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Self.cardShadowBleed
            ),
            heightAnchor.constraint(equalToConstant: Self.totalHeight),

            cardSurface.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            cardSurface.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            cardSurface.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            cardSurface.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            cardContainer.heightAnchor.constraint(equalToConstant: Self.totalHeight - Self.cardShadowBleed),

            scrollView.topAnchor.constraint(equalTo: cardSurface.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor),

            pagesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            headerLabel.topAnchor.constraint(equalTo: cardSurface.topAnchor, constant: Self.headerTopInset),
            headerLabel.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor, constant: Self.horizontalInset),

            listenButton.heightAnchor.constraint(equalToConstant: Self.listenButtonHeight),
            listenButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            listenButton.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor, constant: -Self.horizontalInset),
            listenButton.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor, constant: -Self.footerBottomInset),

            pageControl.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor, constant: -8),
            pageControl.centerYAnchor.constraint(equalTo: cardSurface.centerYAnchor),
        ])
    }

    private func configureListenButton() {
        listenButton.translatesAutoresizingMaskIntoConstraints = false
        listenButton.setTitle("Listen", for: .normal)
        listenButton.accessibilityLabel = "Listen to dialogue"

        let appearance = PrimaryButton.appearance(for: .yellow)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .fixed
        config.background.cornerRadius = 10
        config.background.backgroundColor = appearance.backgroundColor
        config.background.strokeColor = appearance.strokeColor
        config.background.strokeWidth = appearance.strokeWidth
        config.baseForegroundColor = appearance.titleColor
        config.title = "Listen"
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 14, weight: .bold)
            attributes.foregroundColor = appearance.titleColor
            return attributes
        }
        listenButton.configuration = config
        listenButton.configurationUpdateHandler = { button in
            var updated = button.configuration
            let highlighted = button.isHighlighted || button.isSelected
            updated?.background.backgroundColor = highlighted
                ? appearance.highlightedBackgroundColor
                : appearance.backgroundColor
            button.configuration = updated
        }
    }

    private func applyCardShadow() {
        cardContainer.layer.cornerRadius = Self.cardCornerRadius
        cardContainer.layer.cornerCurve = .continuous
        cardContainer.layer.shadowColor = UIColor.black.cgColor
        cardContainer.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.18
        cardContainer.layer.shadowRadius = 14
        cardContainer.layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    // MARK: - Pages

    private func rebuildPages() {
        pagesStack.arrangedSubviews.forEach { view in
            pagesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        scrollView.isScrollEnabled = pages.count > 1
        scrollView.alwaysBounceVertical = pages.count > 1
        scrollView.alwaysBounceHorizontal = false

        for page in pages {
            let pageView = makePageView(for: page)
            pagesStack.addArrangedSubview(pageView)
            NSLayoutConstraint.activate([
                pageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])
        }
    }

    private func makePageView(for page: DialoguePage) -> UIView {
        let font = Self.dialogueJapaneseFont

        let displayInsets = JapaneseFuriganaBuilder.dialogueScrollDisplayInsets(for: font)

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.numberOfLines = 0
        japaneseLabel.textAlignment = .center
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        japaneseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        japaneseLabel.setContentHuggingPriority(.required, for: .vertical)
        japaneseLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let attributed = NSMutableAttributedString(
            attributedString: JapaneseFuriganaBuilder.dialogueScrollAttributedString(
                for: page.japanese,
                font: font,
                textColor: .label
            )
        )
        Self.applyCenterAlignment(to: attributed)

        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: attributed,
            contentInsets: displayInsets
        )

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.addSubview(japaneseLabel)

        let labelWidth = japaneseLabel.widthAnchor.constraint(
            equalTo: container.widthAnchor,
            constant: -(Self.labelSideInset * 2)
        )
        labelWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            japaneseLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            japaneseLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            labelWidth,
            japaneseLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.labelMaxWidth),
        ])
        return container
    }

    private static func applyCenterAlignment(to attributed: NSMutableAttributedString) {
        guard attributed.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let style: NSMutableParagraphStyle
        if let existing = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
           let mutable = existing.mutableCopy() as? NSMutableParagraphStyle {
            style = mutable
        } else {
            style = NSMutableParagraphStyle()
        }
        style.alignment = .center
        attributed.addAttribute(.paragraphStyle, value: style, range: fullRange)
    }

    private static func makePages(scenario: GrammarScenario, example: GrammarExample) -> [DialoguePage] {
        let pages = scenario.lines.map {
            DialoguePage(japanese: $0.japanese)
        }
        if pages.isEmpty, !example.japanese.isEmpty {
            return [DialoguePage(japanese: example.japanese)]
        }
        return pages
    }

    // MARK: - Page control

    @objc private func pageControlChanged(_ sender: UIPageControl) {
        scrollToPage(sender.currentPage, animated: true)
    }

    private func scrollToPage(_ page: Int, animated: Bool) {
        guard pages.indices.contains(page) else { return }
        let pageHeight = max(scrollView.bounds.height, 1)
        let offset = CGPoint(x: 0, y: CGFloat(page) * pageHeight)
        scrollView.setContentOffset(offset, animated: animated)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncPageControlFromScrollOffset()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncPageControlFromScrollOffset()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        syncPageControlFromScrollOffset()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        syncPageControlFromScrollOffset()
    }

    private func syncPageControlFromScrollOffset() {
        guard pages.count > 0 else {
            pageControl.currentPage = 0
            return
        }
        let pageHeight = max(scrollView.bounds.height, 1)
        let page = Int(round(scrollView.contentOffset.y / pageHeight))
        let clampedPage = min(max(page, 0), pages.count - 1)
        pageControl.currentPage = clampedPage
        guard activePageIndex != clampedPage else { return }
        activePageIndex = clampedPage
        pageChangeHaptic.selectionChanged()
        pageChangeHaptic.prepare()
    }
}
