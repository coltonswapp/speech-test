@testable import CommonUsesGatewayPayload
import Foundation
import XCTest

final class CommonUsesGatewayPayloadTests: XCTestCase {

    func testDecodesTokenizedHeardExample() throws {
        let result = try CommonUsesGatewayPayload.decode(fixtureJSON(tokenized: true))
        XCTAssertEqual(result.inThisSentence, "Used to say something is definitely the case.")
        XCTAssertEqual(result.otherUses, ["確かに聞いた (たしかにきいた) — I definitely heard it"])
        XCTAssertEqual(result.examples.count, 1)
        let example = try XCTUnwrap(result.examples.first)
        XCTAssertEqual(example.japanese, "確かに聞いた")
        XCTAssertEqual(example.english, "I definitely heard it")
        XCTAssertEqual(example.tokens.map(\.surface), ["確かに", "聞いた"])
        XCTAssertEqual(example.tokens.map(\.lemma), ["確かに", "聞く"])
        XCTAssertTrue(CommonUsesExampleNavigation.tokensMapOntoJapanese(example))
        XCTAssertEqual(
            CommonUsesExampleNavigation.utf16Slice(example.japanese, start: 3, end: 6),
            "聞いた"
        )
        XCTAssertEqual(CommonUsesExampleNavigation.sentence(for: example), "確かに聞いた")
        XCTAssertNil(CommonUsesExampleNavigation.wordLookupSurface(for: example))
        let heard = try XCTUnwrap(example.tokens.last)
        XCTAssertEqual(CommonUsesExampleNavigation.displayedSurface(for: heard), "聞いた")
        XCTAssertEqual(CommonUsesExampleNavigation.dictionaryLookupSurface(for: heard), "聞く")
    }

    func testDecodesPunctuationAndMultiKanjiExample() throws {
        let json = """
        {
          "inThisSentence": "Used to talk about hearing something.",
          "otherUses": ["え、図書館で聞いた。 (え、としょかんできいた。) — Huh, I heard it at the library."],
          "kanjiNote": "",
          "examples": [
            {
              "japanese": "え、図書館で聞いた。",
              "reading": "え、としょかんできいた。",
              "english": "Huh, I heard it at the library.",
              "tokens": [
                {"surface": "え", "lemma": "え", "reading": "え", "start": 0, "end": 1},
                {"surface": "図書館", "lemma": "図書館", "reading": "としょかん", "start": 2, "end": 5},
                {"surface": "で", "lemma": "で", "reading": "で", "start": 5, "end": 6},
                {"surface": "聞いた", "lemma": "聞く", "reading": "きいた", "start": 6, "end": 9}
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try CommonUsesGatewayPayload.decode(json)
        let example = try XCTUnwrap(result.examples.first)
        XCTAssertEqual(example.tokens.map(\.surface), ["え", "図書館", "で", "聞いた"])
        XCTAssertTrue(CommonUsesExampleNavigation.tokensMapOntoJapanese(example))
        XCTAssertEqual(
            CommonUsesExampleNavigation.utf16Slice(example.japanese, start: 2, end: 5),
            "図書館"
        )
        XCTAssertEqual(
            CommonUsesExampleNavigation.displayedSurface(for: example.tokens[3]),
            "聞いた"
        )
        XCTAssertEqual(
            CommonUsesExampleNavigation.dictionaryLookupSurface(for: example.tokens[3]),
            "聞く"
        )
        XCTAssertNil(CommonUsesExampleNavigation.wordLookupSurface(for: example))
    }

    func testLegacyStringExamplesStayDisplayableWithoutPretendingTheyAreAWord() throws {
        let json = """
        {
          "inThisSentence": "Used to say something is definitely the case.",
          "otherUses": ["確かに聞いた (たしかにきいた) — I definitely heard it"],
          "kanjiNote": ""
        }
        """.data(using: .utf8)!
        let result = try CommonUsesGatewayPayload.decode(json)
        XCTAssertEqual(result.otherUses, ["確かに聞いた (たしかにきいた) — I definitely heard it"])
        let example = try XCTUnwrap(result.examples.first)
        XCTAssertEqual(example.japanese, "確かに聞いた")
        XCTAssertTrue(example.tokens.isEmpty)
        XCTAssertFalse(CommonUsesExampleNavigation.tokensMapOntoJapanese(example))
        XCTAssertEqual(CommonUsesExampleNavigation.sentence(for: example), "確かに聞いた")
        XCTAssertNil(CommonUsesExampleNavigation.wordLookupSurface(for: example))
    }

    func testMalformedTokensDoNotFailTheRestOfThePayload() throws {
        let json = """
        {
          "inThisSentence": "Used to say something is definitely the case.",
          "otherUses": ["確かに聞いた — I definitely heard it"],
          "kanjiNote": "",
          "examples": [
            {
              "japanese": "確かに聞いた",
              "reading": "たしかにきいた",
              "english": "I definitely heard it",
              "tokens": "not-an-array"
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try CommonUsesGatewayPayload.decode(json)
        XCTAssertEqual(result.examples.first?.japanese, "確かに聞いた")
        XCTAssertEqual(result.examples.first?.tokens, [])
        XCTAssertEqual(CommonUsesExampleNavigation.sentence(for: result.examples[0]), "確かに聞いた")
        XCTAssertNil(CommonUsesExampleNavigation.wordLookupSurface(for: result.examples[0]))
    }

    private func fixtureJSON(tokenized: Bool) -> Data {
        let tokens = tokenized
            ? """
              "tokens": [
                {"surface": "確かに", "lemma": "確かに", "reading": "たしかに", "start": 0, "end": 3},
                {"surface": "聞いた", "lemma": "聞く", "reading": "きいた", "start": 3, "end": 6}
              ]
              """
            : """
              "tokens": []
              """
        return """
        {
          "inThisSentence": "Used to say something is definitely the case.",
          "otherUses": ["確かに聞いた (たしかにきいた) — I definitely heard it"],
          "kanjiNote": "",
          "examples": [
            {
              "japanese": "確かに聞いた",
              "reading": "たしかにきいた",
              "english": "I definitely heard it",
              \(tokens)
            }
          ]
        }
        """.data(using: .utf8)!
    }
}
