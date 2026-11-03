//
//  MascotExpression.swift
//  shizen
//
//  Data model for the flower mascot. An expression is one value per animatable
//  knob; `MascotView` springs its current values toward whatever it is given.
//

import CoreGraphics
import Foundation

/// One animatable knob on the mascot.
enum MascotParam: Int, CaseIterable {
    // Look
    case lookX, lookY
    // Eyes
    case openness, lid, lidTilt, sclera, eyeSize, smile, wink
    // Brows
    case browTilt
    // Body
    case tilt, peek
    // Accessories
    case sparks, question, snooze
    // Look (appended so raw values of the cases above stay put)
    case ponder
    // Body
    case busy
    // Accessories
    case exclaim

    enum Group: CaseIterable {
        case look, eyes, brows, body, accessories

        var title: String {
            switch self {
            case .look: return "Look"
            case .eyes: return "Eyes"
            case .brows: return "Brows"
            case .body: return "Body"
            case .accessories: return "Accessories"
            }
        }
    }

    var group: Group {
        switch self {
        case .lookX, .lookY, .ponder: return .look
        case .openness, .lid, .lidTilt, .sclera, .eyeSize, .smile, .wink: return .eyes
        case .browTilt: return .brows
        case .tilt, .peek, .busy: return .body
        case .sparks, .question, .snooze, .exclaim: return .accessories
        }
    }

    var title: String {
        switch self {
        case .lookX: return "Look X (← →)"
        case .lookY: return "Look Y (↑ ↓)"
        case .openness: return "Openness (blink)"
        case .lid: return "Lid (top cut)"
        case .lidTilt: return "Lid tilt"
        case .sclera: return "Whites"
        case .eyeSize: return "Eye size"
        case .smile: return "Smile arc (+ ^  − u)"
        case .wink: return "Wink (left eye)"
        case .browTilt: return "Brow tilt"
        case .tilt: return "Head tilt"
        case .peek: return "Peek"
        case .sparks: return "Sparks"
        case .question: return "Question mark"
        case .snooze: return "Snooze (Z's)"
        case .ponder: return "Ponder (glance ← →)"
        case .busy: return "Busy (working)"
        case .exclaim: return "Exclamation mark"
        }
    }

    var range: ClosedRange<CGFloat> {
        switch self {
        case .lookX, .lookY, .lidTilt, .smile, .browTilt, .tilt: return -1...1
        case .openness, .lid, .sclera, .wink, .peek, .sparks, .question, .snooze, .ponder, .busy, .exclaim: return 0...1
        case .eyeSize: return 0.6...1.6
        }
    }

    var defaultValue: CGFloat {
        switch self {
        // Whites on by default, so classic eyes keep whites and pupils between expressions
        // instead of dropping to solid ink. (Solid-white-eye mode ignores this.)
        case .openness, .eyeSize, .sclera: return 1
        default: return 0
        }
    }
}

struct MascotExpression: Equatable {
    /// Indexed by `MascotParam.rawValue`.
    var values: [CGFloat]

    init(_ overrides: [MascotParam: CGFloat] = [:]) {
        values = MascotParam.allCases.map { overrides[$0] ?? $0.defaultValue }
    }

    subscript(param: MascotParam) -> CGFloat {
        get { values[param.rawValue] }
        set { values[param.rawValue] = newValue }
    }

    var lookX: CGFloat { self[.lookX] }
    var lookY: CGFloat { self[.lookY] }
    var openness: CGFloat { self[.openness] }
    var lid: CGFloat { self[.lid] }
    var lidTilt: CGFloat { self[.lidTilt] }
    var sclera: CGFloat { self[.sclera] }
    var eyeSize: CGFloat { self[.eyeSize] }
    var smile: CGFloat { self[.smile] }
    var wink: CGFloat { self[.wink] }
    var browTilt: CGFloat { self[.browTilt] }
    var tilt: CGFloat { self[.tilt] }
    var peek: CGFloat { self[.peek] }
    var sparks: CGFloat { self[.sparks] }
    var question: CGFloat { self[.question] }
    var snooze: CGFloat { self[.snooze] }
    var ponder: CGFloat { self[.ponder] }
    var busy: CGFloat { self[.busy] }
    var exclaim: CGFloat { self[.exclaim] }

    /// Paste-able Swift for the current tuning (only non-default knobs).
    var swiftSnippet: String {
        let parts = MascotParam.allCases.compactMap { param -> String? in
            let value = self[param]
            guard abs(value - param.defaultValue) > 0.005 else { return nil }
            return ".\(param): \(String(format: "%.2f", Double(value)))"
        }
        return parts.isEmpty ? "MascotExpression()" : "MascotExpression([\(parts.joined(separator: ", "))])"
    }
}

enum MascotEyeSide {
    case left, right

    /// -1 left, +1 right, matching screen x.
    var sign: CGFloat { self == .left ? -1 : 1 }
}

/// A one-shot animation layered on top of an expression.
enum MascotFlourish {
    /// Petals flick round like a fidget spinner.
    case spin
    /// Left eye closes into an arc, holds, and reopens.
    case wink
}

/// The expressions from the design sheet.
enum MascotPreset: CaseIterable {
    case neutral, happy, excited, curious
    case thinking, surprised, focused, skeptical
    case confused, pleased, calm, determined
    case sleepy, wink, lookingLeft, lookingRight, peek
    case working

    var title: String {
        switch self {
        case .neutral: return "Neutral"
        case .happy: return "Happy"
        case .excited: return "Excited"
        case .curious: return "Curious"
        case .thinking: return "Thinking"
        case .surprised: return "Surprised"
        case .focused: return "Focused"
        case .skeptical: return "Skeptical"
        case .confused: return "Confused"
        case .pleased: return "Pleased"
        case .calm: return "Calm"
        case .determined: return "Determined"
        case .sleepy: return "Sleepy"
        case .wink: return "Wink"
        case .lookingLeft: return "Looking Left"
        case .lookingRight: return "Looking Right"
        case .peek: return "Peek"
        case .working: return "Working"
        }
    }

    /// One-shot flourish played by `MascotView.play(_:)` on top of the expression.
    var flourish: MascotFlourish? {
        switch self {
        case .excited: return .spin
        case .wink: return .wink
        default: return nil
        }
    }

    var expression: MascotExpression {
        switch self {
        case .neutral:
            return MascotExpression()
        case .happy:
            return MascotExpression([.smile: 1])
        case .excited:
            return MascotExpression([.smile: 1, .sparks: 1, .lookY: -0.3, .tilt: -0.1])
        case .curious:
            return MascotExpression([.sclera: 1, .lookX: 0.7, .lookY: -0.35])
        case .thinking:
            return MascotExpression([.sclera: 1, .lookY: -0.8, .tilt: -0.1, .ponder: 1])
        case .surprised:
            // Big whites, pupils lifted toward the top rim.
            return MascotExpression([.eyeSize: 1.25, .lookY: -0.35, .exclaim: 1])
        case .focused:
            return MascotExpression([.sclera: 1, .lid: 0.42, .lookX: 0.3, .lookY: 0.4])
        case .skeptical:
            return MascotExpression([.sclera: 1, .lid: 0.4, .lidTilt: 0.8, .lookX: 0.8, .lookY: 0.5, .tilt: 0.2])
        case .confused:
            return MascotExpression([.sclera: 1, .lookX: 0.5, .lookY: -0.1, .tilt: -0.25, .question: 1])
        case .pleased:
            return MascotExpression([.smile: 0.65, .lookY: 0.25])
        case .calm:
            return MascotExpression([.smile: -1])
        case .determined:
            // A low lid narrows the whites under the brows; pupils dead ahead.
            return MascotExpression([.browTilt: 1, .eyeSize: 0.92, .lid: 0.28, .lookY: 0.1])
        case .sleepy:
            return MascotExpression([.smile: -1, .lookY: 1, .tilt: 0.08, .snooze: 1])
        case .wink:
            // Both eyes open; the wink itself is the preset's flourish.
            return MascotExpression([.sclera: 1, .lookX: 0.7])
        case .lookingLeft:
            return MascotExpression([.sclera: 1, .lookX: -1])
        case .lookingRight:
            return MascotExpression([.sclera: 1, .lookX: 1])
        case .peek:
            return MascotExpression([.peek: 1, .lookY: -0.2])
        case .working:
            // Head down, slightly furrowed, eyes scanning while the petals turn like a gear.
            // With whites, the scan reads as pupils sweeping along the bottom of the eye.
            return MascotExpression([.lookY: 0.7, .lid: 0.3, .browTilt: 0.3, .busy: 1])
        }
    }
}
