//
//  SenseSuggestionScrollHint.swift
//  shizen
//
//  Glass pill that slides up from the bottom of a scroll view when the
//  suggested dictionary sense (the pulsing yellow dot) sits below the fold.
//  Tapping it scrolls to the row; it leaves once the row has been seen.
//

import UIKit

/// Points the learner at a suggested sense row that is scrolled out of view below.
final class SenseSuggestionScrollHint: UIView {
    private static let bottomGap: CGFloat = 14
    /// How much of the row must clear the pill before it counts as seen.
    private static let seenPeek: CGFloat = 12
    private static let slideDistance: CGFloat = 90
    /// The row must sit at least this fraction of the visible height below the fold before
    /// the pill appears, so a row that's only just off-screen doesn't trigger it.
    private static let farBelowFraction: CGFloat = 0.5

    private let glassView: UIVisualEffectView
    private let dot = SenseSuggestionDot()
    private let titleLabel = UILabel()
    private let chevron = UIImageView()

    private weak var scrollView: UIScrollView?
    private weak var target: UIView?
    private var offsetObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?
    private var isShowing = false
    /// Once the row has been on screen (or the pill tapped), the hint stays away.
    private var isRetired = false

    override init(frame: CGRect) {
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        glassView = UIVisualEffectView(effect: glass)
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        isHidden = true

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.cornerConfiguration = .capsule()
        addSubview(glassView)

        titleLabel.text = "Best fit below"
        titleLabel.font = Self.roundedFont(.subheadline, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        chevron.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
                .applying(UIImage.SymbolConfiguration(weight: .bold))
        )
        chevron.tintColor = .secondaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [dot, titleLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Suggested meaning below"
        accessibilityHint = "Scrolls to the definition that best fits this sentence."

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Tracking

    /// Watches `scrollView` and slides in while `target` is below the visible area.
    /// The pill is added to the scroll view's superview so it stays put while content scrolls.
    func track(_ target: UIView, in scrollView: UIScrollView) {
        stopTracking()
        guard let host = scrollView.superview else { return }
        self.target = target
        self.scrollView = scrollView
        isRetired = false

        if superview !== host {
            removeFromSuperview()
            host.addSubview(self)
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                bottomAnchor.constraint(
                    equalTo: host.safeAreaLayoutGuide.bottomAnchor,
                    constant: -Self.bottomGap
                ),
                widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -40),
            ])
        }
        host.bringSubviewToFront(self)

        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.refresh()
        }
        sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            self?.refresh()
        }
        // Let the row land in the layout before the first check.
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    /// Hides the pill and stops watching the scroll view.
    func stopTracking() {
        offsetObservation?.invalidate()
        offsetObservation = nil
        sizeObservation?.invalidate()
        sizeObservation = nil
        target = nil
        scrollView = nil
        setShowing(false, animated: false)
    }

    /// Re-checks the row's position (e.g. after the content above it changed height).
    func refresh() {
        guard !isRetired, let scrollView, let target, target.window != nil, window != nil else {
            setShowing(false, animated: window != nil)
            return
        }
        let rowFrame = target.convert(target.bounds, to: scrollView)
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        let pillClearance = bounds.height + Self.bottomGap
        let rowTopShowing = rowFrame.minY + Self.seenPeek <= visibleBottom - pillClearance

        if rowTopShowing {
            // The learner has seen it; don't nag if they scroll back up.
            if isShowing || scrollView.isTracking || scrollView.isDecelerating {
                isRetired = true
            }
            setShowing(false, animated: true)
            return
        }
        // Once up, stay up until the row is seen; otherwise only appear when it's well out of reach.
        let visibleHeight = scrollView.bounds.height
            - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom
        let distanceBelowFold = rowFrame.minY - visibleBottom
        if isShowing || distanceBelowFold >= visibleHeight * Self.farBelowFraction {
            setShowing(true, animated: true)
        }
    }

    // MARK: - Presentation

    private func setShowing(_ showing: Bool, animated: Bool) {
        guard showing != isShowing else { return }
        isShowing = showing
        dot.setSuggested(showing)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let offscreen = reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: Self.slideDistance)

        if showing {
            isHidden = false
            superview?.bringSubviewToFront(self)
            if animated {
                transform = offscreen
                alpha = reduceMotion ? 0 : 1
                UIView.animate(
                    withDuration: 0.55,
                    delay: 0.15,
                    usingSpringWithDamping: 0.78,
                    initialSpringVelocity: 0.4,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    self.transform = .identity
                    self.alpha = 1
                }
            } else {
                transform = .identity
                alpha = 1
            }
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        } else if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = offscreen
                self.alpha = 0
            } completion: { _ in
                guard !self.isShowing else { return }
                self.isHidden = true
                self.transform = .identity
            }
        } else {
            alpha = 0
            transform = .identity
            isHidden = true
        }
    }

    @objc private func tapped() {
        guard let scrollView, let target else { return }
        isRetired = true
        setShowing(false, animated: true)
        let rowFrame = target.convert(target.bounds, to: scrollView)
        let visibleHeight = scrollView.bounds.height
            - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom
        // Land the row a third of the way down so the senses around it stay in view.
        let desiredTop = rowFrame.minY - visibleHeight / 3
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(
            minY,
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        )
        let y = min(max(desiredTop, minY), maxY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
    }

    private static func roundedFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        var descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        if let rounded = descriptor.withDesign(.rounded) {
            descriptor = rounded
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
    }
}
