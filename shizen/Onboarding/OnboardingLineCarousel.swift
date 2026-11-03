//
//  OnboardingLineCarousel.swift
//  shizen
//
//  A vertical carousel of prebuilt lines, one per detent: the focused line sits centered in
//  a clipped window with soft top and bottom edges, and neighbors slide through as the
//  selection changes. Used by the level slider and "Textbooks vs. real life".
//

import UIKit

final class OnboardingLineCarousel: UIView {

    /// Swipe up/down or a tap on a neighbor. The owner decides whether to follow.
    var onSelect: ((Int) -> Void)?
    /// A tap on the focused line itself.
    var onTapFocused: (() -> Void)?
    /// Laid out alongside each move so the window's height change carries its neighbors.
    weak var layoutRoot: UIView?

    private(set) var selectedIndex = 0
    private(set) var lineViews: [UIView] = []

    private let column = UIStackView()
    private var columnTop: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private let fade = CAGradientLayer()
    private var isPlaced = false

    /// Soft fade at the window's top and bottom edges. Only the focused line shows at rest;
    /// neighbors are spaced to sit just outside and only pass through while changing.
    private static let peek: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        column.axis = .vertical
        column.spacing = 28
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        let height = heightAnchor.constraint(equalToConstant: 160)
        height.priority = .defaultHigh
        self.height = height
        let top = column.topAnchor.constraint(equalTo: topAnchor)
        columnTop = top
        NSLayoutConstraint.activate([
            top,
            height,
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        layer.mask = fade

        for direction in [UISwipeGestureRecognizer.Direction.up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces every line. Placement waits for `placeIfNeeded` once there's a real width.
    func setLines(_ views: [UIView], selectedIndex: Int) {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        lineViews = views
        views.forEach { column.addArrangedSubview($0) }
        self.selectedIndex = selectedIndex
        isPlaced = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let edge = bounds.height > 0 ? min(0.45, Self.peek / bounds.height) : 0.2
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        CATransaction.commit()
    }

    /// Call from the owner's `viewDidLayoutSubviews`: places the lines once the window has a
    /// real width to lay them out in.
    func placeIfNeeded() {
        guard !isPlaced, bounds.width > 0 else { return }
        isPlaced = true
        update(animated: false)
    }

    func select(_ index: Int, animated: Bool) {
        guard lineViews.indices.contains(index) else { return }
        selectedIndex = index
        update(animated: animated)
    }

    /// Slides the column so the selected line sits centered in the window. The window is
    /// sized to the tallest line plus its soft edges, so its height never changes with the
    /// selection. Neighbors shrink and dim as they slide through.
    private func update(animated: Bool) {
        guard lineViews.indices.contains(selectedIndex) else { return }
        // Measured rather than read from frames: lines swapped in by `setLines` haven't been
        // laid out yet, and reading their frames would collapse the window.
        let fitting = CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let heights = lineViews.map {
            $0.systemLayoutSizeFitting(fitting, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        let tallest = heights.max() ?? 0
        // Centered on a shorter line, the window shows extra room above and below it; keep the
        // neighbors past that room (and the fade) so none peeks in.
        let spacing = ((tallest - (heights.min() ?? 0)) / 2 + Self.peek + 6).rounded(.up)
        column.spacing = spacing
        let windowHeight = tallest + Self.peek * 2
        height?.constant = windowHeight
        // Scaling is around the center, so the focused line's midpoint holds whatever its transform is.
        let above = heights[..<selectedIndex].reduce(0, +) + spacing * CGFloat(selectedIndex)
        columnTop?.constant = windowHeight / 2 - (above + heights[selectedIndex] / 2)

        let selected = selectedIndex
        let apply = {
            for (index, view) in self.lineViews.enumerated() {
                let distance = abs(index - selected)
                view.alpha = distance == 0 ? 1 : distance == 1 ? 0.35 : 0.12
                view.transform = distance == 0 ? .identity : CGAffineTransform(scaleX: 0.9, y: 0.9)
            }
            (self.layoutRoot ?? self.superview ?? self).layoutIfNeeded()
        }
        guard animated else {
            apply()
            return
        }
        UIViewPropertyAnimator(duration: 0.55, dampingRatio: 0.82, animations: apply).startAnimation()
    }

    /// Swipe up for the next line down the list, down for the one above.
    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        let target = selectedIndex + (gesture.direction == .up ? 1 : -1)
        guard lineViews.indices.contains(target) else { return }
        onSelect?(target)
    }

    /// Tapping a neighbor brings it to the center.
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: column)
        guard let index = lineViews.firstIndex(where: { $0.frame.contains(point) }) else { return }
        if index == selectedIndex {
            onTapFocused?()
        } else {
            onSelect?(index)
        }
    }
}
