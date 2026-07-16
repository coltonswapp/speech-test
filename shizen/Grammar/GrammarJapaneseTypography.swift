//
//  GrammarJapaneseTypography.swift
//  shizen
//
//  Shared Japanese text sizing for grammar lesson examples and prompts.
//

import UIKit

enum GrammarJapaneseTypography {

    /// Example rows in the principle intro list (paired with subheadline English).
    static var listExampleFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .headline)
        return .systemFont(ofSize: base.pointSize + 2, weight: .medium)
    }

    /// English gloss paired with `listExampleFont` in example rows and scenarios.
    static var listExampleEnglishFont: UIFont {
        .preferredFont(forTextStyle: .subheadline)
    }

    /// Payoff line in scenario cards — same size as list examples, slightly heavier.
    static var listExamplePayoffFont: UIFont {
        let base = listExampleFont
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }

    /// Tight gap between Japanese and English in example rows.
    static let listExampleJapaneseEnglishSpacing: CGFloat = 4

    /// Extra cell padding below example rows to balance furigana above (not between JP/EN).
    static var listExampleRowBottomInset: CGFloat {
        8
    }

    /// Inline scenario speaker tag (e.g. "B:") beside dialogue.
    static var scenarioSpeakerFont: UIFont {
        .preferredFont(forTextStyle: .caption1)
    }

    /// Top padding above the speaker + Japanese line only (not the English gloss).
    static let scenarioDialogueTopPadding: CGFloat = 14

    /// Bottom padding below each scenario dialogue block.
    static let scenarioLineBottomPadding: CGFloat = 6

    /// Gap below a dialogue block, above the next divider.
    static let scenarioLineSpacing: CGFloat = 8

    /// Extra gap between a divider and the Japanese dialogue line below it.
    static let scenarioDividerToDialogueSpacing: CGFloat = 14

    /// Italic subheadline for scenario setting / section labels.
    static var scenarioLabelFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }


    /// ScrubbableSentenceView featured example — fixed large size (not paired to English body).
    static var scrubbableFeaturedFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title1)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }

    /// Drill prompts that show a Japanese sentence (furigana-capable).
    static var drillPromptFont: UIFont {
        .systemFont(ofSize: 26, weight: .semibold)
    }

    /// Plain drill sentence display without furigana layout.
    static var drillSentenceFont: UIFont {
        .systemFont(ofSize: 24, weight: .medium)
    }

    /// Japanese line in a usage formality ladder.
    static var usageLadderFont: UIFont {
        .systemFont(ofSize: 20, weight: .regular)
    }

    /// Maximum wrapped lines for usage-ladder Japanese examples.
    static let usageLadderMaxLines = 2

    /// English gloss above grammar multiple-choice options.
    static var drillEnglishPromptFont: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    /// Dictionary lemma in form-choice drills (e.g. たべる).
    static var formChoiceLemmaFont: UIFont {
        .systemFont(ofSize: 22, weight: .semibold)
    }

    /// English intent under the lemma (e.g. "don't drink").
    static var formChoiceIntentFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }
}
