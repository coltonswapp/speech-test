//
//  GrammarFormChoicePromptView.swift
//  shizen
//
//  Form-choice lemma prompt: dictionary verb plus learner-facing gloss from content.
//

import UIKit

/// Displays prompts like `のむ` + `(to drink)` or `つかう` + `(to use), as in "Can I use?"`.
/// When the prompt is only `lemma (to verb)`, the second line is inferred from the correct
/// choice (e.g. prohibition → "don't drink"). Any trailing text after the gloss stays as written.
final class GrammarFormChoicePromptView: UIView {

    private static let verticalPadding: CGFloat = 16
    private static let lemmaIntentSpacing: CGFloat = 6

    init(prompt: String, correctChoice: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = Self.attributedPrompt(prompt: prompt, correctChoice: correctChoice)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func attributedPrompt(prompt: String, correctChoice: String) -> NSAttributedString {
        let lemmaFont = GrammarJapaneseTypography.formChoiceLemmaFont
        let intentFont = GrammarJapaneseTypography.formChoiceIntentFont

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = lemmaIntentSpacing

        guard let parsed = parse(prompt), !parsed.lemma.isEmpty else {
            return NSAttributedString(
                string: prompt,
                attributes: [
                    .font: lemmaFont,
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraph,
                ]
            )
        }

        let subtitle = subtitleLine(parsed: parsed, correctChoice: correctChoice)
        let result = NSMutableAttributedString(
            string: parsed.lemma,
            attributes: [
                .font: lemmaFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]
        )

        guard !subtitle.isEmpty else { return result }

        result.append(NSAttributedString(
            string: "\n\(subtitle)",
            attributes: [
                .font: intentFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]
        ))
        return result
    }

    private struct ParsedPrompt {
        let lemma: String
        let gloss: String
        let suffix: String
    }

    private static func parse(_ text: String) -> ParsedPrompt? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let glossStart = trimmed.range(of: " (") else {
            return ParsedPrompt(lemma: trimmed, gloss: "", suffix: "")
        }

        let lemma = String(trimmed[..<glossStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        let afterOpen = String(trimmed[glossStart.upperBound...])
        guard let closeIndex = afterOpen.firstIndex(of: ")") else {
            return ParsedPrompt(lemma: trimmed, gloss: "", suffix: "")
        }

        let gloss = String(afterOpen[..<closeIndex]).trimmingCharacters(in: .whitespaces)
        let suffix = String(afterOpen[afterOpen.index(after: closeIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return ParsedPrompt(lemma: lemma, gloss: gloss, suffix: suffix)
    }

    private static func subtitleLine(parsed: ParsedPrompt, correctChoice: String) -> String {
        if !parsed.suffix.isEmpty {
            return contentDrivenSubtitle(gloss: parsed.gloss, suffix: parsed.suffix)
        }

        let englishVerb = englishVerb(from: parsed.gloss)
        return intentPhrase(englishVerb: englishVerb, correctChoice: correctChoice)
    }

    private static func contentDrivenSubtitle(gloss: String, suffix: String) -> String {
        guard !gloss.isEmpty else { return suffix }
        return "(\(gloss))\(suffix.hasPrefix(",") ? "" : " ")\(suffix)"
    }

    private static func englishVerb(from gloss: String) -> String {
        let lower = gloss.lowercased()
        if lower.hasPrefix("to ") {
            return String(gloss.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return gloss
    }

    private static func intentPhrase(englishVerb: String, correctChoice: String) -> String {
        let verb = englishVerb.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !verb.isEmpty else { return "" }

        if correctChoice.contains("なくちゃ") || correctChoice.contains("なきゃ") {
            return "have to \(verb)"
        }
        return "don't \(verb)"
    }
}
