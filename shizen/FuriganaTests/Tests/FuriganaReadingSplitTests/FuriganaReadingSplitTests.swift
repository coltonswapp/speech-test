import FuriganaReadingSplit
import XCTest

final class RubyReadingSplitTests: XCTestCase {
    func testConfidentSplitHiga() {
        XCTAssertEqual(
            RubyReadingSplit.confidentKanjiReadingPieces(fullKanjiReading: "ひが", kanjiCount: 2),
            ["ひ", "が"]
        )
    }

    func testAmbiguousGakushokuStaysUnsplit() {
        XCTAssertNil(
            RubyReadingSplit.confidentKanjiReadingPieces(fullKanjiReading: "がくしょく", kanjiCount: 2)
        )
    }

    func testIdeographicSpaceRequiresExactRejoin() {
        XCTAssertEqual(
            RubyReadingSplit.ideographicSpaceParts(for: "つか\u{3000}さま"),
            ["つか", "さま"]
        )
        XCTAssertNil(RubyReadingSplit.ideographicSpaceParts(for: "つか\u{3000}"))
    }

    func testSingleKanjiNeverConfidentSplits() {
        XCTAssertNil(
            RubyReadingSplit.confidentKanjiReadingPieces(fullKanjiReading: "きょう", kanjiCount: 1)
        )
    }

    func testOkuriganaKanji() {
        let aligned = RubyReadingSplit.alignReadingToKanjiAndKana(
            runs: [RubyReadingSplit.SurfaceRun.kanji(0), .kana("じ")],
            reading: "かんじ"
        )
        XCTAssertEqual(aligned?.map(\.reading), ["かん"])
        XCTAssertEqual(aligned?.map(\.kanjiIndex), [0])
    }

    func testOkuriganaVerb() {
        let aligned = RubyReadingSplit.alignReadingToKanjiAndKana(
            runs: [RubyReadingSplit.SurfaceRun.kanji(0), .kana("べる")],
            reading: "たべる"
        )
        XCTAssertEqual(aligned?.map(\.reading), ["た"])
    }

    func testMultiKanjiBeforeOkurigana() {
        let aligned = RubyReadingSplit.alignReadingToKanjiAndKana(
            runs: [RubyReadingSplit.SurfaceRun.kanji(0), .kanji(1), .kana("わり")],
            reading: "ひがわり"
        )
        XCTAssertEqual(aligned?.map(\.reading), ["ひ", "が"])
    }
}
