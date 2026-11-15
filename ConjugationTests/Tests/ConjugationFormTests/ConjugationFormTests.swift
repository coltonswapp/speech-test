@testable import ConjugationForm
import XCTest

/// Tags below are copied from the bundled jmdict.sqlite, including its truncated labels.
final class ConjugationFormTests: XCTestCase {
    private func name(
        _ surface: String,
        lemma: String,
        reading: String? = nil,
        tags: String?
    ) -> String? {
        ConjugationForm.identify(surface: surface, lemma: lemma, lemmaReading: reading, tags: tags)?.name
    }

    // MARK: - Godan

    func testKiku() {
        let tags = "v5k transitive verb"
        XCTAssertEqual(name("聞きました", lemma: "聞く", tags: tags), "Polite past")
        XCTAssertEqual(name("聞く", lemma: "聞く", tags: tags), "Dictionary form")
        XCTAssertEqual(name("聞いた", lemma: "聞く", tags: tags), "Past")
        XCTAssertEqual(name("聞かない", lemma: "聞く", tags: tags), "Negative")
        XCTAssertEqual(name("聞かなかった", lemma: "聞く", tags: tags), "Negative past")
        XCTAssertEqual(name("聞いて", lemma: "聞く", tags: tags), "Te-form")
        XCTAssertEqual(name("聞いている", lemma: "聞く", tags: tags), "Progressive")
        XCTAssertEqual(name("聞いてる", lemma: "聞く", tags: tags), "Progressive")
        XCTAssertEqual(name("聞きたい", lemma: "聞く", tags: tags), "Want to")
        XCTAssertEqual(name("聞こう", lemma: "聞く", tags: tags), "Volitional")
        XCTAssertEqual(name("聞けば", lemma: "聞く", tags: tags), "Conditional")
        XCTAssertEqual(name("聞いたら", lemma: "聞く", tags: tags), "Conditional")
        XCTAssertEqual(name("聞ける", lemma: "聞く", tags: tags), "Potential")
        XCTAssertEqual(name("聞けました", lemma: "聞く", tags: tags), "Potential, polite past")
        XCTAssertEqual(name("聞かれる", lemma: "聞く", tags: tags), "Passive")
        XCTAssertEqual(name("聞かせる", lemma: "聞く", tags: tags), "Causative")
        XCTAssertEqual(name("聞かされる", lemma: "聞く", tags: tags), "Causative-passive")
    }

    func testKanaSurfaceMatchesKanjiLemmaThroughReading() {
        XCTAssertEqual(name("ききました", lemma: "聞く", reading: "きく", tags: "v5k transitive verb"), "Polite past")
    }

    func testGodanTeTaByEnding() {
        XCTAssertEqual(name("読んだ", lemma: "読む", tags: "v5m transitive verb"), "Past")
        XCTAssertEqual(name("読んでる", lemma: "読む", tags: "v5m transitive verb"), "Progressive")
        XCTAssertEqual(name("泳いで", lemma: "泳ぐ", tags: "v5g intransitive verb"), "Te-form")
        XCTAssertEqual(name("待った", lemma: "待つ", tags: "v5t intransitive verb"), "Past")
        XCTAssertEqual(name("待たされる", lemma: "待つ", tags: "v5t intransitive verb"), "Causative-passive")
        XCTAssertEqual(name("買って", lemma: "買う", tags: "v5u transitive verb"), "Te-form")
        XCTAssertEqual(name("買わない", lemma: "買う", tags: "v5u transitive verb"), "Negative")
        XCTAssertEqual(name("死んだ", lemma: "死ぬ", tags: "v5n intransitive verb"), "Past")
        XCTAssertEqual(name("遊んで", lemma: "遊ぶ", tags: "v5b intransitive verb"), "Te-form")
        XCTAssertEqual(name("帰りました", lemma: "帰る", tags: "v5r intransitive verb"), "Polite past")
        XCTAssertEqual(name("話した", lemma: "話す", tags: "v5s transitive verb"), "Past")
    }

    func testSuEndingIsNotMisreadAsMasu() {
        // 覚ました is the plain past of 覚ます, not 〜ました.
        XCTAssertEqual(name("覚ました", lemma: "覚ます", tags: "v5s transitive verb"), "Past")
        XCTAssertEqual(name("覚ましました", lemma: "覚ます", tags: "v5s transitive verb"), "Polite past")
        // No short causative-passive for す verbs.
        XCTAssertNil(name("話さされる", lemma: "話す", tags: "v5s transitive verb"))
    }

    func testIku() {
        let tags = "Godan verb - Iku/Yuk intransitive verb"
        XCTAssertEqual(name("行った", lemma: "行く", tags: tags), "Past")
        XCTAssertEqual(name("行って", lemma: "行く", tags: tags), "Te-form")
        XCTAssertEqual(name("行きます", lemma: "行く", tags: tags), "Polite")
        XCTAssertNil(name("行いた", lemma: "行く", tags: tags))
    }

    func testAruSpecial() {
        let tags = "Godan verb - -aru sp intransitive verb honorific or respectful (sonkeigo) language"
        XCTAssertEqual(name("いらっしゃいます", lemma: "いらっしゃる", tags: tags), "Polite")
        XCTAssertEqual(name("いらっしゃい", lemma: "いらっしゃる", tags: tags), "Imperative")
        XCTAssertEqual(name("いらっしゃった", lemma: "いらっしゃる", tags: tags), "Past")
    }

    func testAruIrregularNegative() {
        let tags = "v5r-i intransitive verb word usually written using kana alone"
        XCTAssertEqual(name("ありました", lemma: "有る", reading: "ある", tags: tags), "Polite past")
        XCTAssertEqual(name("なかった", lemma: "有る", reading: "ある", tags: tags), "Negative past")
        XCTAssertEqual(name("ない", lemma: "有る", reading: "ある", tags: tags), "Negative")
    }

    // MARK: - Readings

    func testKuruReadingsUseTheRightStem() {
        let tags = "Kuru verb - special  intransitive verb"
        func reading(_ surface: String, lemma: String = "来る", lemmaReading: String = "くる") -> String? {
            ConjugationForm.reading(surface: surface, lemma: lemma, lemmaReading: lemmaReading, tags: tags)
        }
        XCTAssertEqual(reading("来ました"), "きました")   // was くりました
        XCTAssertEqual(reading("来ます"), "きます")
        XCTAssertEqual(reading("来た"), "きた")
        XCTAssertEqual(reading("来て"), "きて")
        XCTAssertEqual(reading("来ている"), "きている")
        XCTAssertEqual(reading("来たい"), "きたい")
        XCTAssertEqual(reading("来ない"), "こない")
        XCTAssertEqual(reading("来よう"), "こよう")
        XCTAssertEqual(reading("来られる"), "こられる")
        XCTAssertEqual(reading("来させる"), "こさせる")
        XCTAssertEqual(reading("来い"), "こい")
        XCTAssertEqual(reading("来れば"), "くれば")
        XCTAssertEqual(reading("来る"), "くる")
        XCTAssertEqual(reading("きました"), "きました")   // kana surface stays as is
        XCTAssertEqual(reading("持って来ました", lemma: "持って来る", lemmaReading: "もってくる"), "もってきました")
        XCTAssertNil(reading("来ましたか"))
    }

    func testReadingForOtherClasses() {
        XCTAssertEqual(
            ConjugationForm.reading(surface: "聞きました", lemma: "聞く", lemmaReading: "きく", tags: "v5k transitive verb"),
            "ききました"
        )
        XCTAssertEqual(
            ConjugationForm.reading(surface: "勉強した", lemma: "勉強", lemmaReading: "べんきょう", tags: "n noun or participle w transitive verb"),
            "べんきょうした"
        )
    }

    // MARK: - Ichidan

    func testTaberu() {
        let tags = "v1 transitive verb"
        XCTAssertEqual(name("食べた", lemma: "食べる", tags: tags), "Past")
        XCTAssertEqual(name("食べません", lemma: "食べる", tags: tags), "Polite negative")
        XCTAssertEqual(name("食べませんでした", lemma: "食べる", tags: tags), "Polite negative past")
        XCTAssertEqual(name("食べられる", lemma: "食べる", tags: tags), "Passive or potential")
        XCTAssertEqual(name("食べれる", lemma: "食べる", tags: tags), "Potential")
        XCTAssertEqual(name("食べさせる", lemma: "食べる", tags: tags), "Causative")
        XCTAssertEqual(name("食べさせられる", lemma: "食べる", tags: tags), "Causative-passive")
        XCTAssertEqual(name("食べよう", lemma: "食べる", tags: tags), "Volitional")
        XCTAssertEqual(name("食べろ", lemma: "食べる", tags: tags), "Imperative")
        XCTAssertEqual(name("食べましょう", lemma: "食べる", tags: tags), "Polite volitional")
        XCTAssertEqual(name("食べていました", lemma: "食べる", tags: tags), "Polite past progressive")
    }

    func testKureruImperative() {
        let tags = "Ichidan verb - kurer transitive verb word usually written using kana alone"
        XCTAssertEqual(name("くれ", lemma: "くれる", tags: tags), "Imperative")
    }

    // MARK: - Irregular

    func testKuru() {
        let tags = "Kuru verb - special  intransitive verb"
        XCTAssertEqual(name("来た", lemma: "来る", tags: tags), "Past")
        XCTAssertEqual(name("来ない", lemma: "来る", tags: tags), "Negative")
        XCTAssertEqual(name("来ます", lemma: "来る", tags: tags), "Polite")
        XCTAssertEqual(name("来い", lemma: "来る", tags: tags), "Imperative")
        XCTAssertEqual(name("来られる", lemma: "来る", tags: tags), "Passive or potential")
        // Kana surfaces use the reading: き〜 / こ〜 / く〜.
        XCTAssertEqual(name("きた", lemma: "来る", reading: "くる", tags: tags), "Past")
        XCTAssertEqual(name("こない", lemma: "来る", reading: "くる", tags: tags), "Negative")
        XCTAssertEqual(name("くれば", lemma: "来る", reading: "くる", tags: tags), "Conditional")
    }

    func testSuru() {
        let tags = "vs-i"
        XCTAssertEqual(name("した", lemma: "する", tags: tags), "Past")
        XCTAssertEqual(name("します", lemma: "する", tags: tags), "Polite")
        XCTAssertEqual(name("できる", lemma: "する", tags: tags), "Potential")
        XCTAssertEqual(name("させられる", lemma: "する", tags: tags), "Causative-passive")
    }

    func testSuruNoun() {
        let tags = "n noun or participle w transitive verb"
        XCTAssertEqual(name("勉強しました", lemma: "勉強", tags: tags), "Polite past")
        XCTAssertEqual(name("勉強する", lemma: "勉強", tags: tags), "する verb")
        XCTAssertEqual(name("べんきょうした", lemma: "勉強", reading: "べんきょう", tags: tags), "Past")
        XCTAssertNil(name("勉強", lemma: "勉強", tags: tags))
    }

    // MARK: - i-adjectives

    func testTakai() {
        let tags = "adj-i"
        XCTAssertEqual(name("高い", lemma: "高い", tags: tags), "Dictionary form")
        XCTAssertEqual(name("高かった", lemma: "高い", tags: tags), "Past")
        XCTAssertEqual(name("高くない", lemma: "高い", tags: tags), "Negative")
        XCTAssertEqual(name("高くなかった", lemma: "高い", tags: tags), "Negative past")
        XCTAssertEqual(name("高くて", lemma: "高い", tags: tags), "Te-form")
        XCTAssertEqual(name("高く", lemma: "高い", tags: tags), "Adverb form")
        XCTAssertEqual(name("高ければ", lemma: "高い", tags: tags), "Conditional")
        XCTAssertEqual(name("高そう", lemma: "高い", tags: tags), "Looks like")
        XCTAssertEqual(name("高かったです", lemma: "高い", tags: tags), "Polite past")
    }

    func testIiUsesYoStem() {
        let tags = "adjective (keiyoushi"
        XCTAssertEqual(name("よかった", lemma: "いい", tags: tags), "Past")
        XCTAssertEqual(name("よくない", lemma: "いい", tags: tags), "Negative")
        XCTAssertEqual(name("よさそう", lemma: "いい", tags: tags), "Looks like")
        XCTAssertNil(name("いかった", lemma: "いい", tags: tags))
    }

    // MARK: - No label

    func testNonConjugatingWordsHaveNoForm() {
        XCTAssertNil(name("静か", lemma: "静か", tags: "adj-na"))
        XCTAssertNil(name("水", lemma: "水", tags: "n"))
        XCTAssertNil(name("聞きました", lemma: "聞く", tags: nil))
        XCTAssertNil(name("信じた", lemma: "信ずる", tags: "Ichidan verb - zuru  transitive verb"))
    }

    func testUnknownFormHasNoLabel() {
        // A merged token with a particle is not a form of the verb.
        XCTAssertNil(name("聞きましたか", lemma: "聞く", tags: "v5k transitive verb"))
    }

    func testDetailIncludesEnding() {
        let match = ConjugationForm.identify(surface: "聞きました", lemma: "聞く", tags: "v5k transitive verb")
        XCTAssertEqual(match?.detail, "Past tense, said politely (〜ました).")
    }
}
