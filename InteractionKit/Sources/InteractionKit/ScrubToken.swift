//
//  ScrubToken.swift
//  InteractionKit
//
//  Language-agnostic token + engine hooks for sentence scrub.
//

import UIKit

public struct ScrubToken {
    public let text: String
    public let range: Range<String.Index>

    public init(text: String, range: Range<String.Index>) {
        self.text = text
        self.range = range
    }
}

/// Supplies tokenization, dictionary lookup surfaces, gloss text, and optional ruby.
@MainActor
public protocol ScrubSentenceEngine: AnyObject {
    /// Return tokens immediately, or `nil` to use `tokenizeAsync`.
    func tokenizeSync(_ sentence: String) -> [ScrubToken]?
    func tokenizeAsync(_ sentence: String) async -> [ScrubToken]
    func lookupSurfaces(for tokens: [ScrubToken]) -> [String]
    func gloss(for surface: String) -> String
    func applyRuby(to attributed: NSMutableAttributedString, text: String, font: UIFont)
    var tokenizerDidChangeNotification: Notification.Name? { get }
}
