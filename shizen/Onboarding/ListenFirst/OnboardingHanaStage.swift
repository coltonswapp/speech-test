//
//  OnboardingHanaStage.swift
//  shizen
//
//  One Hana that floats above every onboarding screen, so she can glide from one
//  screen's spot to the next (and into or out of a chat) instead of popping out and
//  back in. Screens park her by handing over a placeholder view: `dock(at:)`.
//
//  Only listen-first v2 has one (`TutorOnboardingSession.hanaStage`).
//

import UIKit

final class OnboardingHanaStage {

    let mascot = TutorChatView.makeMascot()
    private weak var host: UIView?

    var isVisible: Bool { mascot.alpha > 0 }

    /// Puts her on top of `view`, hidden. Call once from the flow's host.
    func install(in view: UIView) {
        mascot.alpha = 0
        view.addSubview(mascot)
        host = view
    }

    /// Keeps her above screens the host adds later.
    func bringToFront() {
        mascot.superview?.bringSubviewToFront(mascot)
    }

    /// Glides (or pops in) to fill `spot`, a placeholder view laid out where she should sit.
    func dock(at spot: UIView, expression: MascotExpression? = nil) {
        if let expression {
            mascot.set(expression)
        }
        spot.superview?.layoutIfNeeded()
        move(to: spot.convert(spot.bounds, to: nil))
    }

    /// Appears at `windowRect` with no animation, e.g. exactly where a chat's own mascot was.
    func appear(at windowRect: CGRect) {
        guard let host else { return }
        let rect = host.convert(windowRect, from: nil)
        mascot.layer.removeAllAnimations()
        mascot.transform = .identity
        mascot.bounds = CGRect(origin: .zero, size: rect.size)
        mascot.center = CGPoint(x: rect.midX, y: rect.midY)
        mascot.alpha = 1
    }

    /// Flies into a chat's first mascot slot, then hands over: `reveal` shows the chat's
    /// own mascot in the same place and she disappears.
    func handOff(to windowRect: CGRect, reveal: @escaping () -> Void) {
        // The chat's mascot starts out thinking (Hana is typing); match it on the way in.
        mascot.set(MascotPreset.thinking.expression)
        move(to: windowRect) { [weak self] in
            reveal()
            self?.mascot.alpha = 0
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        guard animated else {
            mascot.alpha = 0
            return
        }
        UIView.animate(withDuration: 0.25) {
            self.mascot.alpha = 0
            self.mascot.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        } completion: { _ in
            if self.mascot.alpha == 0 {
                self.mascot.transform = .identity
            }
        }
    }

    /// Points her eyes at a point given in window coordinates.
    func look(atWindowPoint point: CGPoint) {
        mascot.look(at: mascot.convert(point, from: nil))
    }

    private func move(to windowRect: CGRect, completion: (() -> Void)? = nil) {
        guard let host else { return }
        bringToFront()
        let rect = host.convert(windowRect, from: nil)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        guard isVisible else {
            mascot.bounds = CGRect(origin: .zero, size: rect.size)
            mascot.center = center
            mascot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(springDuration: 0.5, bounce: 0.35) {
                self.mascot.alpha = 1
                self.mascot.transform = .identity
            } completion: { _ in
                completion?()
            }
            return
        }

        // Redraw at the new size right away and animate a scale back to it, so the
        // layers stay crisp instead of stretching mid-flight.
        let from = mascot.layer.presentation()?.frame ?? mascot.frame
        mascot.layer.removeAllAnimations()
        mascot.bounds = CGRect(origin: .zero, size: rect.size)
        mascot.center = CGPoint(x: from.midX, y: from.midY)
        let scale = rect.width > 0 ? from.width / rect.width : 1
        mascot.transform = CGAffineTransform(scaleX: scale, y: scale)
        UIView.animate(springDuration: 0.6, bounce: 0.2) {
            self.mascot.center = center
            self.mascot.transform = .identity
        } completion: { _ in
            completion?()
        }
    }
}
