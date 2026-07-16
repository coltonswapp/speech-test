//
//  UIViewController+SpeechOverlay.swift
//  shizen
//

import UIKit

extension UIViewController {
    func showSpeechOverlayClip(
        _ clipIndex: Int,
        edge: SpeechProfileOverlayEdge = .top,
        barColor: SpeechOverlayPresenter.BarColor = .blue
    ) {
        SpeechOverlayPresenter.showClip(
            clipIndex,
            from: self,
            edge: edge,
            barColor: barColor
        )
    }
}
