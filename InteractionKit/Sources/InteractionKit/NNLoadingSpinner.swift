//
//  NNLoadingSpinner.swift
//  InteractionKit
//
//  Portable copy from nest-note — drop into any UIKit project
//

import UIKit

public final class NNLoadingSpinner: UIView {

    private let backgroundLayer = CAShapeLayer()
    private let spinningLayer = CAShapeLayer()
    private var rotationDuration: CFTimeInterval = 0.45

    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0
        return imageView
    }()

    private var currentColor: UIColor = .systemBlue

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupSpinner()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSpinner()
    }

    private func setupSpinner() {
        addSubview(stateImageView)
        NSLayoutConstraint.activate([
            stateImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            stateImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6)
        ])

        updatePaths()
        configureLayers()
        startSpinningAnimation()
    }

    private func configureLayers() {
        backgroundLayer.fillColor = UIColor.clear.cgColor
        backgroundLayer.strokeColor = currentColor.withAlphaComponent(0.4).cgColor
        backgroundLayer.lineWidth = 3
        backgroundLayer.lineCap = .round

        spinningLayer.fillColor = UIColor.clear.cgColor
        spinningLayer.strokeColor = currentColor.cgColor
        spinningLayer.lineWidth = 3
        spinningLayer.lineCap = .round
        spinningLayer.strokeEnd = 0.3

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(spinningLayer)
    }

    private func updatePaths() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        ).cgPath

        backgroundLayer.frame = bounds
        backgroundLayer.path = path
        spinningLayer.frame = bounds
        spinningLayer.path = path
    }

    private func startSpinningAnimation() {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = 2 * Double.pi
        rotationAnimation.duration = rotationDuration
        rotationAnimation.repeatCount = .infinity
        rotationAnimation.isRemovedOnCompletion = false
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        spinningLayer.add(rotationAnimation, forKey: "rotation")
    }

    public func setSpeed(duration: CFTimeInterval) {
        rotationDuration = duration
        spinningLayer.removeAnimation(forKey: "rotation")
        startSpinningAnimation()
    }

    public func configure(with color: UIColor) {
        currentColor = color
        backgroundLayer.strokeColor = color.withAlphaComponent(0.4).cgColor
        spinningLayer.strokeColor = color.cgColor
        stateImageView.tintColor = color
    }

    public func reset() {
        backgroundLayer.opacity = 1
        spinningLayer.opacity = 1
        stateImageView.alpha = 0
        stateImageView.transform = .identity
        startSpinningAnimation()
    }

    public func fadeOut(duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        spinningLayer.removeAnimation(forKey: "rotation")
        UIView.animate(withDuration: duration, animations: {
            self.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            completion?()
        })
    }

    public func animateState(success: Bool, completion: (() -> Void)? = nil) {
        let imageName = success ? "checkmark" : "xmark"
        let configuration = UIImage.SymbolConfiguration(pointSize: bounds.width * 0.6, weight: .bold)
        stateImageView.image = UIImage(systemName: imageName, withConfiguration: configuration)?
            .withTintColor(currentColor, renderingMode: .alwaysTemplate)

        spinningLayer.removeAnimation(forKey: "rotation")

        UIView.animate(withDuration: 0.2) {
            self.backgroundLayer.opacity = 0
            self.spinningLayer.opacity = 0
        }

        stateImageView.alpha = 1

        if success {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 1.0)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0.5,
            options: [],
            animations: {
                if success {
                    self.stateImageView.nn_scalePulse(scaleTo: 1.7, duration: 0.15)
                } else {
                    self.stateImageView.nn_errorShake()
                    self.stateImageView.nn_scalePulse(scaleTo: 1.7, duration: 0.15)
                }
            },
            completion: { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    completion?()
                }
            }
        )
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updatePaths()
    }
}

// MARK: - Private animation helpers

private extension UIView {
    func nn_scalePulse(scaleTo: CGFloat, duration: TimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, scaleTo, 1.0]
        animation.keyTimes = [0, 0.5, 1.0]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        animation.duration = duration
        layer.add(animation, forKey: "scaleAnimation")
    }

    func nn_errorShake(angle: CGFloat = 0.1, duration: TimeInterval = 0.4) {
        let radians = angle * .pi
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -radians, radians, -radians / 2, radians / 4, 0]
        animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
        animation.duration = duration
        layer.add(animation, forKey: "errorShakeAnimation")
    }
}
