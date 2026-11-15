@testable import KanaRomanizer
import XCTest

final class KanaRomanizerTests: XCTestCase {
    private func assertRomaji(
        _ cases: [(String, String)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (kana, expected) in cases {
            XCTAssertEqual(KanaRomanizer.romanize(kana), expected, "romanize(\(kana))", file: file, line: line)
        }
    }

    // MARK: - Reported bug

    func testWaterPark() {
        XCTAssertEqual(KanaRomanizer.romanize("ウォーターパーク"), "wootaapaaku")
    }

    // MARK: - Loanword digraphs

    func testWDigraphs() {
        assertRomaji([
            ("ウォ", "wo"), ("ウィ", "wi"), ("ウェ", "we"),
            ("ウィスキー", "wisukii"), ("ウェブ", "webu"), ("ウォッカ", "wokka"),
        ])
    }

    func testFDigraphs() {
        assertRomaji([
            ("ファ", "fa"), ("フィ", "fi"), ("フェ", "fe"), ("フォ", "fo"),
            ("ファン", "fan"), ("フィルム", "firumu"), ("フェリー", "ferii"), ("フォーク", "fooku"),
        ])
    }

    func testTAndDDigraphs() {
        assertRomaji([
            ("ティ", "ti"), ("ディ", "di"), ("トゥ", "tu"), ("ドゥ", "du"),
            ("ティー", "tii"), ("ディズニー", "dizunii"), ("タトゥー", "tatuu"),
        ])
    }

    func testPalatalEDigraphs() {
        assertRomaji([
            ("チェ", "che"), ("シェ", "she"), ("ジェ", "je"),
            ("チェック", "chekku"), ("シェフ", "shefu"), ("ジェット", "jetto"),
        ])
    }

    func testVSounds() {
        assertRomaji([
            ("ヴァ", "va"), ("ヴィ", "vi"), ("ヴ", "vu"), ("ヴェ", "ve"), ("ヴォ", "vo"),
            ("ヴァイオリン", "vaiorin"), ("ヴィーナス", "viinasu"),
        ])
    }

    func testKatakanaYoon() {
        assertRomaji([
            ("キャ", "kya"), ("シュ", "shu"), ("チョ", "cho"), ("ニュ", "nyu"), ("リョ", "ryo"),
            ("キャンプ", "kyanpu"), ("シュート", "shuuto"), ("メニュー", "menyuu"),
        ])
    }

    // MARK: - Long vowel mark

    func testLongVowelRepeatsPreviousVowel() {
        assertRomaji([
            ("カー", "kaa"),       // a
            ("ビール", "biiru"),   // i
            ("スーパー", "suupaa"), // u, a
            ("ケーキ", "keeki"),   // e
            ("ボール", "booru"),   // o
            ("コーヒー", "koohii"),
            ("キャー", "kyaa"),    // after a yoon
            ("ウォー", "woo"),     // after a loanword digraph
        ])
    }

    func testLongVowelWithNoVowelBeforeIt() {
        XCTAssertEqual(KanaRomanizer.romanize("ー"), "-")
        XCTAssertEqual(KanaRomanizer.romanize("ンー"), "n-")
    }

    func testLongVowelInHiragana() {
        XCTAssertEqual(KanaRomanizer.romanize("すごーい"), "sugooi")
    }

    // MARK: - Sokuon

    func testSmallTsuDoublesNextConsonant() {
        assertRomaji([
            ("キップ", "kippu"),
            ("ベッド", "beddo"),
            ("ロッカー", "rokkaa"),
            ("チケット", "chiketto"),
            ("バッグ", "baggu"),
            ("ザッシ", "zasshi"),
            ("マッチャ", "maccha"),
            ("ピッツァ", "pittsa"),
        ])
    }

    func testSmallTsuWithNothingToDouble() {
        XCTAssertEqual(KanaRomanizer.romanize("アッ"), "a")
        XCTAssertEqual(KanaRomanizer.romanize("ッア"), "a")
    }

    // MARK: - Mixed scripts

    func testMixedHiraganaAndKatakana() {
        assertRomaji([
            ("ケーキをたべる", "keekiwotaberu"),
            ("たべるケーキ", "taberukeeki"), // hiragana first: katakana must still convert
            ("コーヒーとおちゃ", "koohiitoocha"),
            ("ウォーターパークにいく", "wootaapaakuniiku"),
        ])
    }

    func testMiddleDotBecomesSpace() {
        XCTAssertEqual(KanaRomanizer.romanize("ウォルト・ディズニー"), "woruto dizunii")
    }

    // MARK: - Small kana never leak

    func testStraySmallKanaReadAsFullSize() {
        assertRomaji([
            ("ォ", "o"), ("ァ", "a"), ("ぃ", "i"), ("ゅ", "yu"), ("ヮ", "wa"),
        ])
    }

    func testOutputNeverContainsKana() {
        let samples = [
            "ウォーターパーク", "ァィゥェォャュョヮッ", "ぁぃぅぇぉゃゅょゎっ",
            "ヴァヴィヴヴェヴォ", "クァクィクェクォ", "ツァツィツェツォ", "イェ",
            "ファイト", "デュエット", "フュージョン", "ヵヶ",
        ]
        for sample in samples {
            let romaji = KanaRomanizer.romanize(sample)
            let kana = romaji.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) }
            XCTAssertTrue(kana.isEmpty, "romanize(\(sample)) = \(romaji) still has kana")
        }
    }

    // MARK: - Hiragana regressions (unchanged from the previous romanizer)

    func testHiraganaUnchanged() {
        assertRomaji([
            ("ありがとう", "arigatou"),
            ("きょう", "kyou"),
            ("しゃしん", "shashin"),
            ("がっこう", "gakkou"),
            ("ちょっと", "chotto"),
            ("きって", "kitte"),
            ("ざっし", "zasshi"),
            ("まっちゃ", "maccha"),
            ("ぢ", "ji"), ("づ", "zu"), ("を", "wo"),
            ("きんえん", "kinen"),
            ("あさ", "asa"),
            ("じゃあね", "jaane"),
            ("りょこう", "ryokou"),
        ])
    }

    func testKatakanaMatchesHiraganaForPlainKana() {
        XCTAssertEqual(KanaRomanizer.romanize("アサ"), KanaRomanizer.romanize("あさ"))
        XCTAssertEqual(KanaRomanizer.romanize("トウキョウ"), "toukyou")
    }

    func testNonKanaPassesThrough() {
        XCTAssertEqual(KanaRomanizer.romanize(""), "")
        XCTAssertEqual(KanaRomanizer.romanize("abc 123"), "abc 123")
    }
}
