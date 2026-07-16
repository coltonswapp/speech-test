import Foundation
import GRDB
import IPADic
import Mecab_Swift
import NaturalLanguage

// MARK: - Minimal JMdict (matches `JMDictStore.hasExactLexicalMatch` / `mustKeepSplit`)

private enum JMDictBridge {
    static let doNotMergeSurfaces: Set<String> = ["いい天気", "良い天気"]

    static func mustKeepSplit(mergedSurface: String) -> Bool {
        doNotMergeSurfaces.contains(mergedSurface)
    }

    static func hasExactLexicalMatch(db: Database, surface: String) throws -> Bool {
        guard !surface.isEmpty else { return false }
        return try Int.fetchOne(
            db,
            sql: """
                SELECT 1 FROM entries
                WHERE expression = ? OR reading = ?
                    OR (primary_reading IS NOT NULL AND primary_reading = ?)
                LIMIT 1
                """,
            arguments: [surface, surface, surface]
        ) != nil
    }
}

// MARK: - Token model (mirror app)

private struct JToken {
    let text: String
    let range: Range<String.Index>
}

// MARK: - NL pipeline (mirror `JapaneseTokenizer`)

private enum NLTokenize {
    private static let doNotSplitTrailingHa: Set<String> = [
        "こんにちは", "こんばんは", "おはよう", "おはようございます", "ありがとう", "ありがとうございます",
    ]

    private static let splitTwoPartLookupPhrases: [(whole: String, first: String, second: String)] = [
        ("いい天気", "いい", "天気"),
        ("良い天気", "良い", "天気"),
    ]

    static func tokenize(_ text: String, tokenizer: NLTokenizer, db: Database) throws -> [JToken] {
        tokenizer.string = text
        var tokens: [JToken] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            let isAllPuncOrSpace = word.unicodeScalars.allSatisfy { s in
                CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.whitespacesAndNewlines.contains(s)
            }
            if !isAllPuncOrSpace, !word.isEmpty {
                tokens.append(JToken(text: word, range: range))
            }
            return true
        }
        var t = splitFinalHaParticle(from: tokens, in: text)
        t = splitAdjectiveNounForLookup(from: t, in: text)
        t = try mergeSplitInflectionTokens(from: t, in: text, db: db)
        return t
    }

    private static func mergeSplitInflectionTokens(from tokens: [JToken], in fullText: String, db: Database) throws -> [JToken] {
        guard tokens.count >= 2 else { return tokens }
        var t = tokens
        var changed = true
        while changed {
            changed = false
            var out: [JToken] = []
            out.reserveCapacity(t.count)
            var i = 0
            while i < t.count {
                if i + 1 < t.count,
                   let merged = try mergePairIfNeeded(t[i], t[i + 1], in: fullText, db: db) {
                    out.append(merged)
                    i += 2
                    changed = true
                } else {
                    out.append(t[i])
                    i += 1
                }
            }
            t = out
        }
        return t
    }

    private static func mergePairIfNeeded(_ a: JToken, _ b: JToken, in fullText: String, db: Database) throws -> JToken? {
        guard a.range.upperBound == b.range.lowerBound else { return nil }
        let mergedRange = a.range.lowerBound..<b.range.upperBound
        let merged = String(fullText[mergedRange])
        guard !merged.isEmpty else { return nil }
        if JMDictBridge.mustKeepSplit(mergedSurface: merged) { return nil }
        if b.text == "は" { return nil }
        let dictHit = try JMDictBridge.hasExactLexicalMatch(db: db, surface: merged)
        let glue = shouldGlueInflectionSuffix(firstText: a.text, secondText: b.text)
        guard glue || dictHit else { return nil }
        return JToken(text: merged, range: mergedRange)
    }

    private static func shouldGlueInflectionSuffix(firstText: String, secondText: String) -> Bool {
        switch secondText {
        case "て", "ちゃ", "ちゃう", "ちゃい", "ちゃった", "ちゃって":
            return true
        case "た":
            return true
        case "ない", "なかった", "なくて", "なければ":
            return true
        case "ましょう", "ます", "ました", "ません", "ませんでした":
            return true
        case "たい", "たく", "たかった":
            return true
        case "で":
            guard let last = firstText.last else { return false }
            return last == "ん" || last == "い" || last == "っ"
        default:
            return false
        }
    }

    private static func splitAdjectiveNounForLookup(from tokens: [JToken], in fullText: String) -> [JToken] {
        var out: [JToken] = []
        out.reserveCapacity(tokens.count + 1)
        for t in tokens {
            if let spec = splitTwoPartLookupPhrases.first(where: { t.text == $0.whole }) {
                let r = t.range
                guard String(fullText[r]) == t.text,
                      let mid = fullText.index(
                          r.lowerBound,
                          offsetBy: spec.first.count,
                          limitedBy: r.upperBound
                      ),
                      mid < r.upperBound
                else {
                    out.append(t)
                    continue
                }
                out.append(JToken(text: spec.first, range: r.lowerBound..<mid))
                out.append(JToken(text: spec.second, range: mid..<r.upperBound))
            } else {
                out.append(t)
            }
        }
        return out
    }

    private static func splitFinalHaParticle(from tokens: [JToken], in fullText: String) -> [JToken] {
        var out: [JToken] = []
        out.reserveCapacity(tokens.count + 2)
        for t in tokens {
            let s = t.text
            if s == "は" || s.count < 2 {
                out.append(t)
                continue
            }
            if doNotSplitTrailingHa.contains(s) {
                out.append(t)
                continue
            }
            if !s.hasSuffix("は") {
                out.append(t)
                continue
            }
            let base = String(s.dropLast())
            if base.isEmpty {
                out.append(t)
                continue
            }
            let r = t.range
            let haStart = fullText.index(before: r.upperBound)
            guard fullText[haStart..<r.upperBound] == "は" else {
                out.append(t)
                continue
            }
            let prefixR = r.lowerBound..<haStart
            out.append(JToken(text: base, range: prefixR))
            out.append(JToken(text: "は", range: haStart..<r.upperBound))
        }
        return out
    }
}

// MARK: - MeCab (mirror app)

private func mecabTokens(for text: String) throws -> [String] {
    let engine = try Tokenizer(dictionary: IPADic())
    return engine.tokenize(text: text, transliteration: .hiragana)
        .filter { !$0.base.isEmpty }
        .filter { ann in
            let word = ann.base
            let isAllPuncOrSpace = word.unicodeScalars.allSatisfy { s in
                CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.whitespacesAndNewlines.contains(s)
            }
            return !isAllPuncOrSpace
        }
        .map(\.base)
}

// MARK: - Run

private let examples: [String] = [
    "今日はいい天気ですね。",
    "歩いて学校へ行きましょう。",
    "蜂蜜は熊の大好物です。",
    "お釣りは三百円です。どうぞ。",
    "こんにちは。お元気ですか。",
    "日本語を勉強しています。",
    "食べられなかったそうです。",
    "新天地で働き始めました。",
    "りんごを三つ買いました。",
    "彼女は東京で生まれましたが、今は大阪に住んでいます。",
]

private func sqliteURL() throws -> URL {
    var u = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        u.deleteLastPathComponent()
    }
    // …/shizen (repo root) → shizen/jmdict.sqlite
    let db = u.appendingPathComponent("shizen/jmdict.sqlite")
    guard FileManager.default.fileExists(atPath: db.path) else {
        throw NSError(domain: "tokenizer_dump", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Missing jmdict.sqlite at \(db.path)",
        ])
    }
    return db
}

@main
enum Entry {
    static func main() throws {
        let dbURL = try sqliteURL()
        var cfg = Configuration()
        cfg.readonly = true
        let queue = try DatabaseQueue(path: dbURL.path, configuration: cfg)
        let nlTok = NLTokenizer(unit: .word)
        nlTok.setLanguage(.japanese)

        print("### Tokenizer example dump (NL + JMdict heuristics vs MeCab IPADic)")
        print("### jmdict: \(dbURL.path)")
        print("")

        for (i, sentence) in examples.enumerated() {
            let nlList = try queue.read { db in
                try NLTokenize.tokenize(sentence, tokenizer: nlTok, db: db)
            }
            let mcList = try mecabTokens(for: sentence)
            print("--- Example \(i + 1) ---")
            print("SENTENCE: \(sentence)")
            print("NL:       \(nlList.map(\.text).joined(separator: " | "))")
            print("MECAB:    \(mcList.joined(separator: " | "))")
            print("")
        }
    }
}
