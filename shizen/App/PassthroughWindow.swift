//
//  PassthroughWindow.swift
//  shizen
//
//  Created by Colton Swapp on 1/16/26.
//

import UIKit

final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        // Let touches pass through empty/root areas of the overlay window.
        return rootViewController?.view == hitView ? nil : hitView
    }
}
