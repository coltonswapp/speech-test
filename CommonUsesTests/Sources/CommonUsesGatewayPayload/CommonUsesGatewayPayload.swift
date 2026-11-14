//
//  CommonUsesGatewayPayload.swift
//  Keep in sync with ../../shizen/Dictionary/CommonUsesGatewayPayload.swift.
//

import Foundation

enum CommonUsesGatewayPayload {

    struct Token: Equatable {
        var surface: String
        var lemma: String
        var reading: String
        var start: Int?
        var end: Int?

        init(surface: String, lemma: String, reading: String, start: Int? = nil, end: Int? = nil) {
            self.surface = surface
            self.lemma = lemma
            self.reading = reading
            self.start = start
            self.end = end
        }
    }

    struct Example: Equatable {
        var japanese: String
        var reading: String
        var english: String
        var tokens: [Token]

        init(japanese: String, reading: String, english: String, tokens: [Token] = []) {
            self.japanese = japanese
            self.reading = reading
            self.english = english
            self.tokens = tokens
        }
    }

    struct Result: Equatable, Decodable {
        var inThisSentence: String
        var otherUses: [String]
        var kanjiNote: String
        var examples: [Example]

        enum CodingKeys: String, CodingKey {
            case inThisSentence, otherUses, kanjiNote, examples
        }

        init(
            inThisSentence: String,
            otherUses: [String],
            kanjiNote: String,
            examples: [Example]
        ) {
            self.inThisSentence = inThisSentence
            self.otherUses = otherUses
            self.kanjiNote = kanjiNote
            self.examples = examples
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inThisSentence = try container.decode(String.self, forKey: .inThisSentence)
            kanjiNote = try container.decodeIfPresent(String.self, forKey: .kanjiNote) ?? ""
            let decodedExamples = (try? container.decode(
                [Example].self,
                forKey: .examples
            )) ?? []
            var parsedExamples = decodedExamples.filter { !$0.japanese.isEmpty }
            if let strings = try? container.decode([String].self, forKey: .otherUses) {
                otherUses = strings
                if parsedExamples.isEmpty {
                    parsedExamples = strings.compactMap(Example.parseDisplayString)
                }
            } else if let objects = try? container.decode([Example].self, forKey: .otherUses) {
                otherUses = objects.compactMap { example in
                    let japanese = example.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !japanese.isEmpty else { return nil }
                    if example.english.isEmpty { return japanese }
                    return example.reading.isEmpty
                        ? "\(japanese) — \(example.english)"
                        : "\(japanese) (\(example.reading)) — \(example.english)"
                }
                if parsedExamples.isEmpty {
                    parsedExamples = objects.filter { !$0.japanese.isEmpty }
                }
            } else {
                otherUses = []
            }
            examples = parsedExamples
        }
    }

    static func decode(_ data: Data) throws -> Result {
        try JSONDecoder().decode(Result.self, from: data)
    }
}

extension CommonUsesGatewayPayload.Token: Decodable {
    enum CodingKeys: String, CodingKey {
        case surface, lemma, reading, start, end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSurface = (try container.decodeIfPresent(String.self, forKey: .surface) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lemmaRaw = (try container.decodeIfPresent(String.self, forKey: .lemma) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        surface = decodedSurface
        lemma = lemmaRaw.isEmpty ? decodedSurface : lemmaRaw
        reading = (try container.decodeIfPresent(String.self, forKey: .reading) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        start = try container.decodeIfPresent(Int.self, forKey: .start)
        end = try container.decodeIfPresent(Int.self, forKey: .end)
    }
}

extension CommonUsesGatewayPayload.Example: Decodable {
    enum CodingKeys: String, CodingKey {
        case japanese, reading, english, tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        japanese = (try container.decodeIfPresent(String.self, forKey: .japanese) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        reading = (try container.decodeIfPresent(String.self, forKey: .reading) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        english = (try container.decodeIfPresent(String.self, forKey: .english) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tokens = (try? container.decode([CommonUsesGatewayPayload.Token].self, forKey: .tokens)) ?? []
    }

    /// Older Common Uses items were a single display string.
    static func parseDisplayString(_ raw: String) -> CommonUsesGatewayPayload.Example? {
        var remainder = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        var english = ""
        for separator in [" — ", " – ", "—", "–"] {
            guard let range = remainder.range(of: separator) else { continue }
            english = String(remainder[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = String(remainder[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        var reading = ""
        if let range = remainder.range(of: #"[\(（]([^)）]+)[\)）]\s*$"#, options: .regularExpression) {
            reading = String(remainder[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "()（） \t"))
            remainder = String(remainder[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !remainder.isEmpty else { return nil }
        return CommonUsesGatewayPayload.Example(
            japanese: remainder,
            reading: reading,
            english: english,
            tokens: []
        )
    }
}

/// Common Uses examples open as tokenized sentences, never as one vocabulary word.
enum CommonUsesExampleNavigation {
    static func sentence(for example: CommonUsesGatewayPayload.Example) -> String? {
        let japanese = example.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        return japanese.isEmpty ? nil : japanese
    }

    /// Whole-example word lookup is never used, including for phrases like 確かに聞いた.
    static func wordLookupSurface(for example: CommonUsesGatewayPayload.Example) -> String? {
        guard sentence(for: example) != nil else { return nil }
        return nil
    }

    /// Displayed token surface (聞いた), not the lemma (聞く) and not the whole example.
    static func displayedSurface(for token: CommonUsesGatewayPayload.Token) -> String {
        let surface = token.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        return surface.isEmpty ? token.lemma.trimmingCharacters(in: .whitespacesAndNewlines) : surface
    }

    /// Dictionary lookup form. Lemma wins for conjugations (聞いた → 聞く).
    static func dictionaryLookupSurface(for token: CommonUsesGatewayPayload.Token) -> String {
        let lemma = token.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = displayedSurface(for: token)
        return lemma.isEmpty ? surface : lemma
    }

    static func utf16Slice(_ text: String, start: Int, end: Int) -> String? {
        guard start >= 0, end >= start else { return nil }
        let ns = text as NSString
        guard end <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    static func tokensMapOntoJapanese(_ example: CommonUsesGatewayPayload.Example) -> Bool {
        guard !example.tokens.isEmpty else { return false }
        return example.tokens.allSatisfy { token in
            let surface = displayedSurface(for: token)
            guard !surface.isEmpty, let start = token.start, let end = token.end else { return false }
            return utf16Slice(example.japanese, start: start, end: end) == surface
        }
    }
}
