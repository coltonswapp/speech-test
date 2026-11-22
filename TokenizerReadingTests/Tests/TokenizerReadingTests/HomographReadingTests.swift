@testable import TokenizerReading
import XCTest

final class HomographReadingTests: XCTestCase {
    func testCherryBlossomNaniIro() {
        assertAgreedReading(
            surface: "何色",
            in: "この桜は何色ですか？",
            expected: "なにいろ"
        )
    }

    func testHowManyColoursNanShoku() {
        assertAgreedReading(
            surface: "何色",
            in: "何色ありますか",
            expected: "なんしょく"
        )
    }

    func testOoguiNotTaishoku() {
        let readings = JapaneseTokenizer.rubyReadings(covering: "大食", in: "大食い")
        XCTAssertEqual(readings, ["おおぐ"])
        XCTAssertFalse(readings.contains("たいしょく"))
        XCTAssertFalse(readings.joined().contains("たいしょく"))
    }

    func testGakushokuNotGakuku() {
        let readings = JapaneseTokenizer.rubyReadings(covering: "学食", in: "学食")
        XCTAssertEqual(readings, ["がくしょく"])
        XCTAssertFalse(readings.contains("がくく"))
        XCTAssertEqual(readings.joined(), "がくしょく")
    }

    private func assertAgreedReading(surface: String, in sentence: String, expected: String) {
        let sentenceRuby = JapaneseTokenizer.rubyReadings(covering: surface, in: sentence)
        XCTAssertEqual(
            sentenceRuby,
            [expected],
            "sentence ruby for \(surface) in \(sentence)"
        )

        let headerRuby = JapaneseTokenizer.furiganaAnnotations(for: surface, inSentence: sentence)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map(\.reading)
        XCTAssertEqual(
            headerRuby,
            [expected],
            "header ruby for \(surface) in \(sentence)"
        )

        let kana = JMDictStore.shared.kanaReadingForDisplay(
            surface: surface,
            matching: nil,
            inSentence: sentence
        )
        XCTAssertEqual(kana, expected, "kanaReadingForDisplay for \(surface) in \(sentence)")
        XCTAssertEqual(sentenceRuby, headerRuby)
        XCTAssertEqual(headerRuby.joined(), kana)
    }
}
