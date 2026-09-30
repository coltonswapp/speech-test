import InteractionKit
import UIKit

/// Circular glass icon button. Content slides through a clipped circle.
/// Loading sends the glyph up and brings the spinner in from below; ending
/// the load reverses that. `transitionSymbol(to:direction:)` uses the same
/// slide so a control can point at a panel that opens above or below it.
/// Calling it again for the other symbol reverses an in-flight slide.
final class GlassIconButton: UIButton {

    /// Way the outgoing glyph leaves the face. Incoming content enters from the opposite edge.
    enum GlyphSlideDirection {
        case up
        case down

        fileprivate func exitY(travel: CGFloat) -> CGFloat {
            switch self {
            case .up: return -travel
            case .down: return travel
            }
        }

        fileprivate func entranceY(travel: CGFloat) -> CGFloat {
            switch self {
            case .up: return travel
            case .down: return -travel
            }
        }
    }

    private let contentClip = UIView()
    private let glyphView = UIImageView()
    private let alternateGlyphView = UIImageView()
    private let spinner = NNLoadingSpinner(frame: .zero)

    private var glyphPointSize: CGFloat
    private var glyphTint: UIColor
    private var restingSymbol: String
    private var glyphWidthConstraint: NSLayoutConstraint!
    private var glyphHeightConstraint: NSLayoutConstraint!
    private var alternateWidthConstraint: NSLayoutConstraint!
    private var alternateHeightConstraint: NSLayoutConstraint!
    private struct SymbolFlight {
        var atStart: String
        var atEnd: String
    }

    private var isLoading = false
    private var isAnimatingTransition = false
    private var isSymbolAnimating = false
    private var transitionGeneration = 0
    private var symbolTransitionGeneration = 0
    private var transitionAnimator: UIViewPropertyAnimator?
    private var symbolTransitionAnimator: UIViewPropertyAnimator?
    private var symbolFlight: SymbolFlight?

    init(
        symbolName: String,
        pointSize: CGFloat = 22,
        glyphDimension: CGFloat? = nil,
        tintColor: UIColor = .systemYellow,
        accessibilityLabel: String? = nil
    ) {
        glyphPointSize = pointSize
        glyphTint = tintColor
        restingSymbol = symbolName
        super.init(frame: .zero)

        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        configuration = config
        self.accessibilityLabel = accessibilityLabel
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        contentClip.translatesAutoresizingMaskIntoConstraints = false
        contentClip.clipsToBounds = true
        contentClip.isUserInteractionEnabled = false
        contentClip.backgroundColor = .clear

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false

        alternateGlyphView.translatesAutoresizingMaskIntoConstraints = false
        alternateGlyphView.contentMode = .scaleAspectFit
        alternateGlyphView.isUserInteractionEnabled = false
        alternateGlyphView.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isUserInteractionEnabled = false
        spinner.isHidden = true
        spinner.configure(with: tintColor)

        addSubview(contentClip)
        contentClip.addSubview(alternateGlyphView)
        contentClip.addSubview(glyphView)
        contentClip.addSubview(spinner)

        let side = glyphDimension ?? (pointSize + 6)
        glyphWidthConstraint = glyphView.widthAnchor.constraint(equalToConstant: side)
        glyphHeightConstraint = glyphView.heightAnchor.constraint(equalToConstant: side)
        alternateWidthConstraint = alternateGlyphView.widthAnchor.constraint(equalToConstant: side)
        alternateHeightConstraint = alternateGlyphView.heightAnchor.constraint(equalToConstant: side)

        NSLayoutConstraint.activate([
            contentClip.topAnchor.constraint(equalTo: topAnchor),
            contentClip.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentClip.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentClip.bottomAnchor.constraint(equalTo: bottomAnchor),

            glyphView.centerXAnchor.constraint(equalTo: contentClip.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: contentClip.centerYAnchor),
            glyphWidthConstraint,
            glyphHeightConstraint,

            alternateGlyphView.centerXAnchor.constraint(equalTo: contentClip.centerXAnchor),
            alternateGlyphView.centerYAnchor.constraint(equalTo: contentClip.centerYAnchor),
            alternateWidthConstraint,
            alternateHeightConstraint,

            spinner.centerXAnchor.constraint(equalTo: contentClip.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentClip.centerYAnchor),
            spinner.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.42),
            spinner.heightAnchor.constraint(equalTo: spinner.widthAnchor),
        ])

        applySymbol(symbolName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(
        _ systemName: String,
        pointSize: CGFloat? = nil,
        glyphDimension: CGFloat? = nil,
        tintColor: UIColor? = nil
    ) {
        if let pointSize {
            glyphPointSize = pointSize
        }
        if let glyphDimension {
            glyphWidthConstraint.constant = glyphDimension
            glyphHeightConstraint.constant = glyphDimension
            alternateWidthConstraint.constant = glyphDimension
            alternateHeightConstraint.constant = glyphDimension
        } else if let pointSize {
            let side = pointSize + 6
            glyphWidthConstraint.constant = side
            glyphHeightConstraint.constant = side
            alternateWidthConstraint.constant = side
            alternateHeightConstraint.constant = side
        }
        if let tintColor {
            glyphTint = tintColor
            spinner.configure(with: tintColor)
            alternateGlyphView.tintColor = tintColor
        }
        symbolTransitionGeneration += 1
        haltSymbolTransitionAnimator()
        isSymbolAnimating = false
        alternateGlyphView.isHidden = true
        alternateGlyphView.transform = .identity
        restingSymbol = systemName
        applySymbol(systemName)
        if !isLoading, !isAnimatingTransition {
            glyphView.transform = .identity
        }
    }

    /// Slides the current glyph out toward `direction` and brings `systemName` in from the opposite edge.
    /// Call again with the previous symbol and the opposite direction to reverse the motion.
    /// An in-flight slide reverses in place instead of snapping to a new one.
    func transitionSymbol(
        to systemName: String,
        pointSize: CGFloat? = nil,
        direction: GlyphSlideDirection,
        animated: Bool = true
    ) {
        let pointSizeChanged = pointSize.map { $0 != glyphPointSize } ?? false
        if reverseSymbolTransitionIfNeeded(to: systemName, pointSizeChanged: pointSizeChanged) {
            return
        }
        guard systemName != restingSymbol || pointSizeChanged else { return }
        let outgoingSymbol = restingSymbol
        let outgoingPointSize = glyphPointSize
        restingSymbol = systemName
        if let pointSize {
            glyphPointSize = pointSize
        }

        symbolTransitionGeneration += 1
        let generation = symbolTransitionGeneration
        haltSymbolTransitionAnimator()
        isSymbolAnimating = true

        let side = max(glyphWidthConstraint.constant, 1)
        // Freeze both glyphs as bitmaps. Assigning a new SF Symbol to the
        // on-screen image view morphs it into the destination while the
        // other copy slides, so the outgoing icon must not stay a symbol.
        let outgoingImage = rasterizedSymbol(outgoingSymbol, pointSize: outgoingPointSize, side: side)
        let incomingImage = rasterizedSymbol(systemName, pointSize: glyphPointSize, side: side)

        let travel = bounds.height
        let canSlide = animated && travel > 1 && outgoingSymbol != systemName
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            glyphView.removeAllSymbolEffects()
            alternateGlyphView.removeAllSymbolEffects()
            alternateGlyphView.preferredSymbolConfiguration = nil
            glyphView.preferredSymbolConfiguration = nil
            alternateGlyphView.image = outgoingImage
            alternateGlyphView.tintColor = nil
            alternateGlyphView.isHidden = !canSlide || outgoingImage == nil
            alternateGlyphView.transform = .identity
            if canSlide {
                glyphView.transform = CGAffineTransform(translationX: 0, y: direction.entranceY(travel: travel))
            }
            glyphView.image = incomingImage
            glyphView.tintColor = nil
            if !canSlide, !isLoading {
                glyphView.transform = .identity
            }
        }
        CATransaction.commit()

        guard canSlide else {
            isSymbolAnimating = false
            alternateGlyphView.isHidden = true
            installLiveSymbol(restingSymbol)
            return
        }

        let flight = SymbolFlight(atStart: outgoingSymbol, atEnd: systemName)
        symbolFlight = flight
        let animator = UIViewPropertyAnimator(
            duration: 0.45,
            controlPoint1: CGPoint(x: 0.76, y: 0),
            controlPoint2: CGPoint(x: 0.24, y: 1)
        ) {
            self.alternateGlyphView.transform = CGAffineTransform(translationX: 0, y: direction.exitY(travel: travel))
            self.glyphView.transform = .identity
        }
        animator.scrubsLinearly = false
        animator.addCompletion { [weak self] _ in
            guard let self, generation == self.symbolTransitionGeneration else { return }
            self.symbolTransitionAnimator = nil
            self.symbolFlight = nil
            let side = max(self.glyphWidthConstraint.constant, 1)
            UIView.performWithoutAnimation {
                // Last request wins, whether the slide finished forward or reversed.
                self.glyphView.image = self.rasterizedSymbol(
                    self.restingSymbol,
                    pointSize: self.glyphPointSize,
                    side: side
                )
                self.glyphView.tintColor = nil
                if !self.isLoading {
                    self.glyphView.transform = .identity
                }
                self.alternateGlyphView.isHidden = true
                self.alternateGlyphView.transform = .identity
                self.alternateGlyphView.image = nil
            }
            self.isSymbolAnimating = false
        }
        symbolTransitionAnimator = animator
        animator.startAnimation()
    }

    /// Reverses a slide that's already running toward the other symbol.
    /// Returns true when this call is fully handled.
    private func reverseSymbolTransitionIfNeeded(to systemName: String, pointSizeChanged: Bool) -> Bool {
        guard !pointSizeChanged,
              let animator = symbolTransitionAnimator,
              animator.state == .active,
              let flight = symbolFlight else { return false }
        let headingTo = animator.isReversed ? flight.atStart : flight.atEnd
        if systemName == headingTo {
            restingSymbol = systemName
            return true
        }
        let headingFrom = animator.isReversed ? flight.atEnd : flight.atStart
        guard systemName == headingFrom else { return false }
        restingSymbol = systemName
        animator.isReversed.toggle()
        return true
    }

    /// Slides the spinner and glyph through the clipped button face.
    /// A button that appears already loading should pass `animated: false` so the spinner is in place, then animate the exit once the fetch finishes.
    func setLoading(_ loading: Bool, animated: Bool = true) {
        guard loading != isLoading else { return }
        isLoading = loading
        transitionGeneration += 1
        let generation = transitionGeneration
        haltTransitionAnimator()
        isAnimatingTransition = false

        if loading {
            spinner.isHidden = false
            spinner.configure(with: glyphTint)
            spinner.reset()
        }

        let travel = bounds.height
        guard animated, travel > 1 else {
            applyRestingTransforms()
            if !loading {
                spinner.isHidden = true
                spinner.reset()
            }
            return
        }

        isAnimatingTransition = true
        if loading {
            spinner.transform = CGAffineTransform(translationX: 0, y: travel)
            glyphView.transform = .identity
        } else {
            spinner.transform = .identity
            glyphView.transform = CGAffineTransform(translationX: 0, y: -travel)
        }

        let animator = UIViewPropertyAnimator(
            duration: 0.45,
            controlPoint1: CGPoint(x: 0.76, y: 0),
            controlPoint2: CGPoint(x: 0.24, y: 1)
        ) {
            if loading {
                self.spinner.transform = .identity
                self.glyphView.transform = CGAffineTransform(translationX: 0, y: -travel)
            } else {
                self.spinner.transform = CGAffineTransform(translationX: 0, y: travel)
                self.glyphView.transform = .identity
            }
        }
        animator.addCompletion { [weak self] _ in
            guard let self, generation == self.transitionGeneration else { return }
            self.transitionAnimator = nil
            self.isAnimatingTransition = false
            guard !self.isLoading else { return }
            self.spinner.isHidden = true
            self.spinner.reset()
        }
        transitionAnimator = animator
        animator.startAnimation()
    }

    private func haltTransitionAnimator() {
        guard let animator = transitionAnimator else { return }
        transitionAnimator = nil
        animator.stopAnimation(true)
    }

    private func haltSymbolTransitionAnimator() {
        guard let animator = symbolTransitionAnimator else { return }
        symbolTransitionAnimator = nil
        symbolFlight = nil
        animator.stopAnimation(true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) / 2
        contentClip.layer.cornerRadius = radius
        contentClip.layer.cornerCurve = .continuous
        bringSubviewToFront(contentClip)
        guard !isAnimatingTransition, !isSymbolAnimating else { return }
        applyRestingTransforms()
    }

    private func applyRestingTransforms() {
        alternateGlyphView.isHidden = true
        alternateGlyphView.transform = .identity
        let travel = bounds.height
        guard travel > 1 else { return }
        if isLoading {
            spinner.transform = .identity
            glyphView.transform = CGAffineTransform(translationX: 0, y: -travel)
        } else {
            spinner.transform = CGAffineTransform(translationX: 0, y: travel)
            glyphView.transform = .identity
        }
    }

    private func installLiveSymbol(_ systemName: String) {
        guard !isSymbolAnimating else { return }
        UIView.performWithoutAnimation {
            applySymbol(systemName)
        }
    }

    /// Draws the symbol into a plain image so a later symbol assignment cannot morph this frame.
    private func rasterizedSymbol(_ systemName: String, pointSize: CGFloat, side: CGFloat) -> UIImage? {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: symbolConfig)?
            .withTintColor(glyphTint, renderingMode: .alwaysOriginal) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        format.opaque = false
        let canvas = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            let symbolSize = symbol.size
            let rect = CGRect(
                x: (canvas.width - symbolSize.width) / 2,
                y: (canvas.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(in: rect)
        }
    }

    private func applySymbol(_ systemName: String) {
        glyphView.removeAllSymbolEffects()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.tintColor = glyphTint
        glyphView.image = UIImage(systemName: systemName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
    }
}
