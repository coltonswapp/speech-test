//
//  FlashcardStackView.swift
//  InteractionKit
//
//  Tinder-style swipeable card stack: right = "know it", left = "review again".
//

import UIKit

public enum FlashcardSwipeDirection {
    case left
    case right

    /// Translation past the screen edge so the card fully clears (with padding for rotation overhang).
    public var offscreenTranslation: CGFloat {
        let distance = UIScreen.main.bounds.width * 1.4
        switch self {
        case .left: return -distance
        case .right: return distance
        }
    }
}

/// Per-card surface hosted by `FlashcardStackView`. Language-specific content lives in the app target.
public protocol StackableFlashcard: UIView {
    var isRevealed: Bool { get }
    func setRevealed(_ revealed: Bool, animated: Bool)
}

public protocol FlashcardStackViewDelegate: AnyObject {
    func flashcardStack(_ stack: FlashcardStackView, didTapCardAt index: Int)
    func flashcardStack(_ stack: FlashcardStackView, didSwipeCardAt index: Int, direction: FlashcardSwipeDirection)
    func flashcardStackDidFinish(_ stack: FlashcardStackView)
}

public final class FlashcardStackView: UIView, UIGestureRecognizerDelegate {

    // MARK: - Tuning

    private let maxVisibleCards = 3
    private let scaleRatio: CGFloat = 0.92
    private let verticalOffset: CGFloat = 28
    private let backgroundRotationRange: ClosedRange<CGFloat> = 2.5...7.5
    private let minimumDismissFraction: CGFloat = 0.35
    private let minimumSwipeVelocity: CGFloat = 600

    // MARK: - State

    private var deckCount = 0
    private var makeCard: ((Int) -> any StackableFlashcard)?
    private var cards: [any StackableFlashcard] = []
    private var currentIndex: Int = 0
    private var activeCard: (any StackableFlashcard)?
    /// Each card keeps its own tilt as it moves through the stack.
    private var cardRotations: [ObjectIdentifier: CGFloat] = [:]

    // MARK: - Subviews

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "All done!"
        label.font = .preferredFont(forTextStyle: .title2)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.alpha = 0
        return label
    }()

    /// Tint overlay drawn on top of the front card while dragging (green right / red left).
    private let dragTintOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        return view
    }()

    public weak var delegate: FlashcardStackViewDelegate?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        clipsToBounds = false

        addSubview(progressLabel)
        addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            progressLabel.topAnchor.constraint(equalTo: topAnchor),
            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.heightAnchor.constraint(equalToConstant: 20),

            emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Public

    public func setDeck(count: Int, makeCard: @escaping (Int) -> any StackableFlashcard) {
        deckCount = count
        self.makeCard = makeCard
        currentIndex = 0
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        cardRotations.removeAll()
        emptyStateLabel.alpha = 0

        let visibleCount = min(maxVisibleCards, count)
        for slot in 0..<visibleCount {
            let card = makeCard(slot)
            assignRotationIfNeeded(for: card)
            cards.append(card)
        }

        // Insert back-to-front so slot 0 is on top.
        for card in cards.reversed() {
            addSubview(card)
            constrainCard(card)
        }

        layoutCards()
        attachGesturesToFrontCard()
        updateProgressLabel()
    }

    public func enumerateVisibleCards(_ body: (any StackableFlashcard) -> Void) {
        cards.forEach(body)
    }

    // MARK: - Card construction & layout

    private func constrainCard(_ card: UIView) {
        card.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = card.widthAnchor.constraint(equalTo: widthAnchor, constant: -40)
        widthConstraint.priority = .required
        let heightCap = card.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.82)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            card.heightAnchor.constraint(equalTo: card.widthAnchor, multiplier: 1.1),
            heightCap,
        ])
    }

    private func assignRotationIfNeeded(for card: UIView) {
        let key = ObjectIdentifier(card)
        guard cardRotations[key] == nil else { return }
        let magnitude = CGFloat.random(in: backgroundRotationRange)
        let sign: CGFloat = Bool.random() ? 1 : -1
        cardRotations[key] = magnitude * sign * .pi / 180
    }

    private func forgetRotation(for card: UIView) {
        cardRotations.removeValue(forKey: ObjectIdentifier(card))
    }

    private func transform(for card: UIView, slot: Int) -> CGAffineTransform {
        let scale = pow(scaleRatio, CGFloat(slot))
        let yOffset = verticalOffset * CGFloat(slot)
        var transform = CGAffineTransform(translationX: 0, y: yOffset).scaledBy(x: scale, y: scale)
        if slot > 0 {
            assignRotationIfNeeded(for: card)
            let rotation = cardRotations[ObjectIdentifier(card)] ?? 0
            transform = transform.rotated(by: rotation)
        }
        return transform
    }

    private func layoutCards() {
        for (index, card) in cards.enumerated() {
            card.layer.zPosition = CGFloat(cards.count - index)
            guard index < maxVisibleCards else {
                card.alpha = 0
                continue
            }
            card.transform = transform(for: card, slot: index)
            card.alpha = 1
        }
    }

    // MARK: - Gestures

    private func attachGesturesToFrontCard() {
        if let previous = activeCard {
            previous.gestureRecognizers?.forEach { previous.removeGestureRecognizer($0) }
            previous.isUserInteractionEnabled = false
            dragTintOverlay.removeFromSuperview()
        }
        guard let top = cards.first else {
            activeCard = nil
            return
        }
        activeCard = top
        top.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        tap.delegate = self
        pan.delegate = self
        top.addGestureRecognizer(tap)
        top.addGestureRecognizer(pan)

        dragTintOverlay.alpha = 0
        top.addSubview(dragTintOverlay)
        NSLayoutConstraint.activate([
            dragTintOverlay.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            dragTintOverlay.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            dragTintOverlay.topAnchor.constraint(equalTo: top.topAnchor),
            dragTintOverlay.bottomAnchor.constraint(equalTo: top.bottomAnchor),
        ])
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let card = activeCard, gesture.view === card else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        card.setRevealed(!card.isRevealed, animated: true)
        delegate?.flashcardStack(self, didTapCardAt: currentIndex)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let card = gesture.view else { return }
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        let width = max(card.bounds.width, 1)

        switch gesture.state {
        case .began, .changed:
            let rotation = (translation.x / width) * (.pi / 10)
            card.transform = CGAffineTransform(translationX: translation.x, y: translation.y * 0.4)
                .rotated(by: rotation)

            let fraction = min(1, abs(translation.x) / width)
            dragTintOverlay.backgroundColor = translation.x >= 0
                ? UIColor.systemGreen.withAlphaComponent(0.35)
                : UIColor.systemRed.withAlphaComponent(0.35)
            dragTintOverlay.alpha = fraction

        case .ended, .cancelled, .failed:
            let fraction = abs(translation.x) / width
            let shouldDismiss = fraction >= minimumDismissFraction || abs(velocity.x) >= minimumSwipeVelocity
            if shouldDismiss {
                let direction: FlashcardSwipeDirection = translation.x >= 0 ? .right : .left
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissFrontCard(direction: direction, exitVelocity: velocity.x)
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.75,
                    initialSpringVelocity: 0.4,
                    options: [.curveEaseOut],
                    animations: {
                        card.transform = self.transform(for: card, slot: 0)
                        self.dragTintOverlay.alpha = 0
                    }
                )
            }

        default:
            break
        }
    }

    // MARK: - Dismissal

    /// `exitVelocity` is the gesture's horizontal velocity in pt/s. Pass 0 for programmatic dismissals.
    private func dismissFrontCard(direction: FlashcardSwipeDirection, exitVelocity: CGFloat = 0) {
        guard let card = cards.first else { return }
        cards.removeFirst()
        let swipedIndex = currentIndex
        currentIndex += 1

        // Pull dragTintOverlay off the outgoing card so it doesn't fly away with it.
        dragTintOverlay.removeFromSuperview()
        dragTintOverlay.alpha = 0

        // Bring the next background card forward if we have more deck to draw from.
        let nextDeckIndex = currentIndex + cards.count
        var incomingBackCard: (any StackableFlashcard)?
        if nextDeckIndex < deckCount, let makeCard {
            let newCard = makeCard(nextDeckIndex)
            assignRotationIfNeeded(for: newCard)
            newCard.alpha = 0
            if let bottom = cards.last {
                insertSubview(newCard, belowSubview: bottom)
            } else {
                addSubview(newCard)
            }
            constrainCard(newCard)
            cards.append(newCard)
            let backSlot = cards.count - 1
            newCard.layer.zPosition = 0
            newCard.transform = transform(for: newCard, slot: backSlot + 1)
            incomingBackCard = newCard
        }

        let target = direction.offscreenTranslation
        let currentX = card.transform.tx
        let currentY = card.transform.ty
        let currentRotation = atan2(card.transform.b, card.transform.a)
        let distanceRemaining = max(abs(target - currentX), 1)
        // Default speed when no velocity (e.g. programmatic) — completes a full-screen slide in ~0.35s.
        let fallbackSpeed: CGFloat = UIScreen.main.bounds.width / 0.35
        let speed = max(abs(exitVelocity), fallbackSpeed)
        let duration = TimeInterval(min(max(distanceRemaining / speed, 0.16), 0.5))

        // Outgoing card: eased slide-out so it decelerates naturally rather than stopping short.
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                card.transform = CGAffineTransform(translationX: target, y: currentY)
                    .rotated(by: currentRotation)
            },
            completion: { _ in
                self.forgetRotation(for: card)
                card.removeFromSuperview()
                self.delegate?.flashcardStack(self, didSwipeCardAt: swipedIndex, direction: direction)
                self.attachGesturesToFrontCard()
                self.updateProgressLabel()
                if self.cards.isEmpty {
                    self.showEmptyState()
                    self.delegate?.flashcardStackDidFinish(self)
                }
            }
        )

        // Rest of the stack (including the newly promoted top card): gentle spring settle,
        // decoupled from the outgoing card's linear-feeling slide so the promotion reads as its own beat.
        UIView.animate(
            withDuration: 0.4,
            delay: 0.05,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction],
            animations: {
                self.layoutCards()
                incomingBackCard?.alpha = 1
            }
        )
    }

    // MARK: - Progress + empty state

    private func updateProgressLabel() {
        if deckCount == 0 {
            progressLabel.text = "0 / 0"
            return
        }
        let displayed = min(currentIndex + 1, deckCount)
        progressLabel.text = "\(displayed) / \(deckCount)"
    }

    private func showEmptyState() {
        UIView.animate(withDuration: 0.3) {
            self.progressLabel.alpha = 0
            self.emptyStateLabel.alpha = 1
        }
    }
}
