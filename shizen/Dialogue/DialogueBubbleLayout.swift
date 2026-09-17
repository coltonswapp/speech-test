//
//  DialogueBubbleLayout.swift
//  shizen
//
//  Shared transcript chrome: A/B sides, column pin, metadata inset, planted scale.
//

import InteractionKit
import UIKit

enum DialogueBubbleLayout {

    static let messageColumnMaxWidthRatio: CGFloat = 0.82
    static let metadataHorizontalInset: CGFloat = 20
    static let sameSpeakerSpacing: CGFloat = 20
    static let speakerChangeSpacing: CGFloat = 48
    static let activeBubbleScale: CGFloat = 1.04
    static let emphasisDuration: TimeInterval = 0.35

    enum MetadataVerticalPin {
        /// Label fills the wrapper (English under a bubble).
        case fill
        /// Label sits on the wrapper's bottom edge so a taller header still
        /// keeps the name on the bubble.
        case bottom
    }

    /// First unseen spoken speaker is leading; the next unique name is trailing.
    @discardableResult
    static func assignSpeakerSide(
        for speaker: String,
        sides: inout [String: DialogueSpeakerSide],
        nextSide: inout DialogueSpeakerSide
    ) -> DialogueSpeakerSide {
        if let existing = sides[speaker] {
            return existing
        }
        let assigned = nextSide
        sides[speaker] = assigned
        nextSide = nextSide == .leading ? .trailing : .leading
        return assigned
    }

    static func spacingAfterSpokenLine(previousSpeaker: String, nextSpeaker: String) -> CGFloat {
        nextSpeaker == previousSpeaker ? sameSpeakerSpacing : speakerChangeSpacing
    }

    @discardableResult
    static func pinMessageColumn(
        _ column: UIView,
        to row: UIView,
        side: DialogueSpeakerSide,
        maxWidthRatio: CGFloat = messageColumnMaxWidthRatio
    ) -> [NSLayoutConstraint] {
        let maxWidth = column.widthAnchor.constraint(
            lessThanOrEqualTo: row.widthAnchor,
            multiplier: maxWidthRatio
        )
        maxWidth.priority = .required
        var constraints: [NSLayoutConstraint] = [
            column.topAnchor.constraint(equalTo: row.topAnchor),
            column.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            maxWidth,
        ]
        switch side {
        case .leading:
            constraints += [
                column.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                column.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            ]
        case .trailing:
            constraints += [
                column.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                column.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    static func insetMetadataWrapper(
        around label: UILabel,
        side: DialogueSpeakerSide,
        verticalPin: MetadataVerticalPin = .fill
    ) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        var constraints: [NSLayoutConstraint] = []
        switch (side, verticalPin) {
        case (.leading, .fill):
            constraints += [
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ]
        case (.trailing, .fill):
            constraints += [
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            ]
        case (.leading, .bottom):
            constraints += [
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            ]
            let hugTop = label.topAnchor.constraint(equalTo: wrapper.topAnchor)
            hugTop.priority = .defaultHigh
            constraints.append(hugTop)
        case (.trailing, .bottom):
            constraints += [
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                label.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
            ]
            let hugTop = label.topAnchor.constraint(equalTo: wrapper.topAnchor)
            hugTop.priority = .defaultHigh
            constraints.append(hugTop)
        }

        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    static func applyBubbleEmphasisTransform(
        to bubble: DialogueJapaneseBubbleView,
        emphasis: CGFloat,
        side: DialogueSpeakerSide
    ) {
        let scale = 1 + (activeBubbleScale - 1) * emphasis
        let transform: CGAffineTransform
        if abs(scale - 1) > 0.001, bubble.bounds.width > 0 {
            let width = bubble.bounds.width
            let dx: CGFloat
            switch side {
            case .leading:
                dx = -width * (1 - scale) / 2
            case .trailing:
                dx = width * (1 - scale) / 2
            }
            transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale)
        } else {
            transform = .identity
        }

        if let container = bubble.superview as? DialogueBubbleSwipeRevealContainer {
            container.setBaseBubbleTransform(transform)
        } else {
            bubble.transform = transform
        }
    }
}
