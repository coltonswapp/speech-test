//
//  CalloutLifecycleChild.swift
//  InteractionKit
//
//  Invisible child VC whose viewWillDisappear tracks the parent leaving the stack.
//

import UIKit

/// Added as a child of the screen hosting a definition callout so we can dismiss
/// the overlay when navigation away begins.
public final class CalloutLifecycleChild: UIViewController {

    public var onHostLeaving: (() -> Void)?

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let parent else { return }
        if parent.isMovingFromParent || parent.isBeingDismissed {
            onHostLeaving?()
        }
    }
}
