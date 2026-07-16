//
//  DialogueLessonLoadingCoordinator.swift
//  shizen
//
//  Owns centered loading chrome (NNLoadingSpinner + label) for dialogue lesson
//  screens so the host view controller stays thin.
//

import UIKit

/// Full-screen loading overlay for a pushed lesson view controller.
final class DialogueLessonLoadingCoordinator {

    private weak var hostView: UIView?
    private let overlayView = UIView()
    private let contentStack = UIStackView()
    private let spinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
    private let label = UILabel()

    private var isAttached = false
    private(set) var isLoading = false

    func attach(to hostView: UIView) {
        self.hostView = hostView

        if !isAttached {
            isAttached = true

            overlayView.translatesAutoresizingMaskIntoConstraints = false
            overlayView.backgroundColor = ExperimentPalette.pageBackground
            overlayView.isUserInteractionEnabled = true
            overlayView.alpha = 0
            overlayView.isHidden = true

            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.axis = .vertical
            contentStack.alignment = .center
            contentStack.spacing = 14

            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.configure(with: .systemYellow)

            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Loading content..."
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 1

            contentStack.addArrangedSubview(spinner)
            contentStack.addArrangedSubview(label)
            overlayView.addSubview(contentStack)

            NSLayoutConstraint.activate([
                contentStack.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
                contentStack.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
                spinner.widthAnchor.constraint(equalToConstant: 36),
                spinner.heightAnchor.constraint(equalToConstant: 36),
            ])
        }

        if overlayView.superview !== hostView {
            overlayView.removeFromSuperview()
            hostView.addSubview(overlayView)
            NSLayoutConstraint.activate([
                overlayView.topAnchor.constraint(equalTo: hostView.topAnchor),
                overlayView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                overlayView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                overlayView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            ])
        }
    }

    /// Shows the overlay immediately at full opacity (no fade-in) so it is
    /// visible for the entire navigation push and short loads.
    func beginLoading() {
        guard isAttached else { return }
        isLoading = true

        spinner.reset()
        spinner.alpha = 1
        contentStack.alpha = 1
        overlayView.isHidden = false
        overlayView.alpha = 1
        overlayView.isUserInteractionEnabled = true
        bringOverlayToFront()
    }

    func finishLoading(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isLoading else {
            completion?()
            return
        }
        isLoading = false
        overlayView.isUserInteractionEnabled = false

        let teardown = { [weak self] in
            guard let self else { return }
            self.overlayView.isHidden = true
            self.overlayView.alpha = 0
            completion?()
        }

        guard animated else {
            teardown()
            return
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.overlayView.alpha = 0
        } completion: { _ in
            teardown()
        }
    }

    func bringOverlayToFront() {
        guard isLoading || !overlayView.isHidden,
              let hostView,
              overlayView.superview === hostView
        else { return }
        hostView.bringSubviewToFront(overlayView)
    }
}
