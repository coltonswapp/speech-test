//
//  KanaDetailCatalog.swift
//  shizen
//
//  soundsLike hints and example vocabulary for hiragana chart glyphs (DEBUG).
//


import Foundation

struct KanaVocabExample: Hashable {
    let japanese: String
    let meaning: String

    var romaji: String { HiraganaRomaji.romanize(japanese) }

    var listLine: String { "\(japanese) • \(romaji) → \(meaning)" }
}

struct KanaDetailItem: Hashable {
    let kana: String
    let romaji: String
    /// e.g. `"ah" as in "father"`
    let soundsLike: String
    let vocabulary: [KanaVocabExample]
}

enum KanaDetailCatalog {

    static func item(kana: String, romaji: String) -> KanaDetailItem {
        if let item = byKana[kana] { return item }
        if KanaScript.detecting(in: kana) == .katakana {
            let hiragana = KanaCurriculum.katakanaToHiragana(kana)
            let soundsLike = byKana[hiragana]?.soundsLike ?? soundsLikePhrase(romaji, word: "romaji")
            let vocabulary = (katakanaVocabulary[kana] ?? []).map {
                KanaVocabExample(japanese: $0.0, meaning: $0.1)
            }
            return KanaDetailItem(kana: kana, romaji: romaji, soundsLike: soundsLike, vocabulary: vocabulary)
        }
        return KanaDetailItem(
            kana: kana,
            romaji: romaji,
            soundsLike: soundsLikePhrase(romaji, word: "romaji"),
            vocabulary: []
        )
    }

    /// Example words starting with this kana, preferring those whose reading begins with the glyph.
    static func vocabularyExamples(
        for kana: String,
        romaji: String,
        maxCount: Int = 4
    ) -> [KanaVocabExample] {
        let item = item(kana: kana, romaji: romaji)
        let startingWithKana = item.vocabulary.filter { $0.japanese.hasPrefix(kana) }
        let pool = startingWithKana.isEmpty ? item.vocabulary : startingWithKana
        return Array(pool.prefix(maxCount))
    }

    private static let byKana: [String: KanaDetailItem] = Dictionary(
        uniqueKeysWithValues: allEntries.map { ($0.kana, $0) }
    )

    private static let allEntries: [KanaDetailItem] = seion + voiced + yoon

    // MARK: - Seion (gojūon)

    private static let seion: [KanaDetailItem] = [
        e("あ", "a", "ah", "father", [("あさ", "morning"), ("あか", "red"), ("あめ", "rain")]),
        e("い", "i", "ee", "see", [("いぬ", "dog"), ("いち", "one"), ("いえ", "house")]),
        e("う", "u", "oo", "flute", [("うみ", "sea"), ("うし", "cow"), ("うた", "song")]),
        e("え", "e", "eh", "bed", [("えき", "station"), ("えんぴつ", "pencil"), ("え", "picture / painting")]),
        e("お", "o", "oh", "go", [("おはよう", "good morning"), ("おちゃ", "tea"), ("おと", "sound")]),

        e("か", "ka", "kah", "car", [("かさ", "umbrella"), ("かわ", "river / skin"), ("かお", "face")]),
        e("き", "ki", "kee", "key", [("き", "tree"), ("きく", "to listen / chrysanthemum"), ("きた", "north")]),
        e("く", "ku", "koo", "cool", [("くつ", "shoes"), ("くも", "cloud / spider"), ("くち", "mouth")]),
        e("け", "ke", "keh", "kettle", [("けさ", "this morning"), ("けん", "sword / ticket"), ("け", "hair (on head)")]),
        e("こ", "ko", "koh", "core", [("こども", "child"), ("ここ", "here"), ("こえ", "voice")]),

        e("さ", "sa", "sah", "sock", [("さかな", "fish"), ("さくら", "cherry blossom"), ("さむい", "cold")]),
        e("し", "shi", "she", "she", [("しろ", "white"), ("しま", "island"), ("しごと", "work")]),
        e("す", "su", "soo", "sue", [("すし", "sushi"), ("すき", "like / empty"), ("すう", "number")]),
        e("せ", "se", "seh", "set", [("せんせい", "teacher"), ("せかい", "world"), ("せ", "back / height")]),
        e("そ", "so", "soh", "soap", [("そら", "sky"), ("そと", "outside"), ("そば", "buckwheat noodles / beside")]),

        e("た", "ta", "tah", "tar", [("たべる", "to eat"), ("たまご", "egg"), ("たかい", "tall / expensive")]),
        e("ち", "chi", "chee", "cheese", [("ちず", "map"), ("ちか", "near / basement"), ("ちいさい", "small")]),
        e("つ", "tsu", "tsoo", "cats", [("つき", "moon"), ("つくえ", "desk"), ("つよい", "strong")]),
        e("て", "te", "teh", "ten", [("て", "hand"), ("てがみ", "letter"), ("てんき", "weather")]),
        e("と", "to", "toh", "toe", [("とり", "bird"), ("ともだち", "friend"), ("とけい", "clock")]),

        e("な", "na", "nah", "knob", [("なつ", "summer"), ("なまえ", "name"), ("なか", "inside")]),
        e("に", "ni", "knee", "knee", [("にほん", "Japan"), ("にく", "meat"), ("にわ", "garden")]),
        e("ぬ", "nu", "noo", "noon", [("ぬの", "cloth"), ("ぬる", "to paint / smear"), ("ぬく", "to extract")]),
        e("ね", "ne", "neh", "net", [("ねこ", "cat"), ("ねる", "to sleep"), ("ね", "root / price")]),
        e("の", "no", "noh", "know", [("のむ", "to drink"), ("のり", "seaweed / to ride"), ("の", "field")]),

        e("は", "ha", "hah", "haha", [("はな", "flower / nose"), ("はし", "bridge / chopsticks"), ("はる", "spring")]),
        e("ひ", "hi", "hee", "heat", [("ひ", "fire"), ("ひる", "noon"), ("ひく", "to pull / play (instrument)")]),
        e("ふ", "fu", "foo", "food", [("ふね", "ship"), ("ふた", "lid"), ("ふゆ", "winter")]),
        e("へ", "he", "heh", "help", [("へや", "room"), ("へた", "unskilled"), ("へび", "snake")]),
        e("ほ", "ho", "hoh", "hoe", [("ほん", "book"), ("ほし", "star"), ("ほしい", "want")]),

        e("ま", "ma", "mah", "mama", [("まち", "town"), ("まど", "window"), ("まつ", "pine / to wait")]),
        e("み", "mi", "mee", "meet", [("みず", "water"), ("みみ", "ear"), ("みる", "to see")]),
        e("む", "mu", "moo", "moon", [("むし", "insect"), ("むかし", "long ago"), ("むり", "impossible")]),
        e("め", "me", "meh", "men", [("め", "eye"), ("めがね", "glasses"), ("めだか", "killifish")]),
        e("も", "mo", "moh", "more", [("もり", "forest"), ("もち", "rice cake"), ("もっと", "more")]),

        e("や", "ya", "yah", "yard", [("やま", "mountain"), ("やさい", "vegetable"), ("やすい", "cheap / restful")]),
        e("ゆ", "yu", "yoo", "you", [("ゆき", "snow"), ("ゆめ", "dream"), ("ゆうびん", "mail")]),
        e("よ", "yo", "yoh", "yoga", [("よる", "night"), ("よむ", "to read"), ("よっと", "heave-ho")]),

        e("ら", "ra", "rah", "raw", [("らく", "comfort / easy"), ("らいねん", "next year"), ("らめん", "ramen")]),
        e("り", "ri", "ree", "read", [("りんご", "apple"), ("りす", "squirrel"), ("りょこう", "travel")]),
        e("る", "ru", "roo", "ruby", [("るす", "absence"), ("るい", "kind / type"), ("る", "to carve / excel")]),
        e("れ", "re", "reh", "red", [("れきし", "history"), ("れい", "example / zero"), ("れんしゅう", "practice")]),
        e("ろ", "ro", "roh", "road", [("ろく", "six"), ("ろうそく", "candle"), ("ろくおん", "recording")]),

        e("わ", "wa", "wah", "water", [("わたし", "I / me"), ("わかる", "to understand"), ("わに", "crocodile")]),
        e("を", "wo", "oh", "oak", [("を", "object marker (written, particle)"), ("ほんをよむ", "read a book"), ("みずをのむ", "drink water")]),
        e("ん", "n", "n", "sing (nasal)", [("ほん", "book"), ("せんせい", "teacher"), ("にほん", "Japan")]),
    ]

    // MARK: - Voiced (dakuten / handakuten)

    private static let voiced: [KanaDetailItem] = [
        e("が", "ga", "gah", "garden", [("がっこう", "school"), ("がくせい", "student"), ("がか", "painter")]),
        e("ぎ", "gi", "gee", "gear", [("ぎん", "silver"), ("ぎゅうにく", "beef"), ("ぎんこう", "bank")]),
        e("ぐ", "gu", "goo", "good", [("ぐあい", "condition"), ("ぐん", "army / group"), ("ぐる", "to turn")]),
        e("げ", "ge", "geh", "get", [("げんき", "healthy / energetic"), ("げんかん", "entryway"), ("げんご", "language")]),
        e("ご", "go", "goh", "go", [("ごはん", "meal / rice"), ("ごめん", "sorry"), ("ごみ", "trash")]),

        e("ざ", "za", "zah", "zap", [("ざっし", "magazine"), ("ざる", "strainer"), ("ざんねん", "too bad")]),
        e("じ", "ji", "jee", "jeep", [("じかん", "time"), ("じしょ", "dictionary"), ("じてんしゃ", "bicycle")]),
        e("ず", "zu", "zoo", "zoo", [("ず", "diagram"), ("ずっと", "continuously"), ("ずこう", "figure / drawing")]),
        e("ぜ", "ze", "zeh", "zen", [("ぜんぶ", "all"), ("ぜん", "good / previous"), ("ぜんしん", "whole body")]),
        e("ぞ", "zo", "zoh", "zone", [("ぞう", "elephant"), ("ぞうきん", "dust cloth"), ("ぞっこう", "favorite")]),

        e("だ", "da", "dah", "dot", [("だいがく", "university"), ("だいすき", "love / really like"), ("だれ", "who")]),
        e("ぢ", "ji", "jee", "jeep (archaic spelling)", [("ちぢむ", "to shrink"), ("はなぢ", "nosebleed"), ("ちぢめる", "to shorten")]),
        e("づ", "zu", "zoo", "zoo (rare)", [("つづく", "to continue"), ("つづける", "to keep doing"), ("つづき", "continuation")]),
        e("で", "de", "deh", "desk", [("でんわ", "telephone"), ("でかい", "huge"), ("でんしゃ", "train")]),
        e("ど", "do", "doh", "dough", [("どうぶつ", "animal"), ("どこ", "where"), ("どうも", "thanks")]),

        e("ば", "ba", "bah", "bob", [("ばなな", "banana"), ("ばしょ", "place"), ("ばか", "fool")]),
        e("び", "bi", "bee", "bee", [("びょうき", "illness"), ("びん", "bottle"), ("びっくり", "surprise")]),
        e("ぶ", "bu", "boo", "boot", [("ぶた", "pig"), ("ぶん", "sentence / part"), ("ぶどう", "grape")]),
        e("べ", "be", "beh", "bed", [("べんきょう", "study"), ("べんとう", "boxed lunch"), ("べんり", "convenient")]),
        e("ぼ", "bo", "boh", "boat", [("ぼく", "I (male)"), ("ぼん", "tray / Bon festival"), ("ぼうし", "hat")]),

        e("ぱ", "pa", "pah", "pop", [("ぱん", "bread"), ("ぱーてぃー", "party"), ("ぱす", "pass")]),
        e("ぴ", "pi", "pee", "peel", [("ぴん", "pin"), ("ぴあの", "piano"), ("ぴくにっく", "picnic")]),
        e("ぷ", "pu", "poo", "pool", [("ぷーる", "pool"), ("ぷりん", "pudding"), ("ぷらす", "plus")]),
        e("ぺ", "pe", "peh", "pet", [("ぺん", "pen"), ("ぺット", "pet"), ("ぺらぺら", "fluent")]),
        e("ぽ", "po", "poh", "pole", [("ぽけっと", "pocket"), ("ぽすと", "post"), ("ぽてと", "potato")]),
    ]

    // MARK: - Yōon

    private static let yoon: [KanaDetailItem] = [
        e("きゃ", "kya", "kyah", "cabin", [("きゃく", "guest"), ("きゃんぷ", "camp"), ("きゃべつ", "cabbage")]),
        e("きゅ", "kyu", "kyoo", "cute", [("きゅう", "nine / ball"), ("きゅうり", "cucumber"), ("きゅうしゅう", "rescue")]),
        e("きょ", "kyo", "kyoh", "Tokyo", [("きょう", "today / capital"), ("きょうみ", "interest"), ("きょか", "permission")]),

        e("しゃ", "sha", "shah", "shock", [("しゃしん", "photo"), ("しゃべる", "to chat"), ("しゃかい", "society")]),
        e("しゅ", "shu", "shoo", "shoe", [("しゅくだい", "homework"), ("しゅみ", "hobby"), ("しゅっぱつ", "departure")]),
        e("しょ", "sho", "shoh", "show", [("しょくどう", "cafeteria"), ("しょうがっこう", "elementary school"), ("しょるい", "document")]),

        e("ちゃ", "cha", "chah", "cha (tea)", [("ちゃ", "tea"), ("ちゃいろ", "brown"), ("ちゃん", "suffix / buddy")]),
        e("ちゅ", "chu", "choo", "chew", [("ちゅう", "middle / insect"), ("ちゅうがっこう", "middle school"), ("ちゅうい", "caution")]),
        e("ちょ", "cho", "choh", "choke", [("ちょっと", "a little"), ("ちょうど", "exactly"), ("ちょきん", "savings")]),

        e("にゃ", "nya", "nyah", "meow", [("にゃん", "meow"), ("にゃんこ", "kitty"), ("にゃー", "meow (sound)")]),
        e("にゅ", "nyu", "nyoo", "new", [("にゅうがく", "enrollment"), ("にゅうじょう", "admission"), ("にゅうし", "entrance exam")]),
        e("にょ", "nyo", "nyoh", "New York", [("にょろにょろ", "wiggly"), ("にょっき", "suddenly appear"), ("にょ", "rare slang")]),

        e("ひゃ", "hya", "hyah", "hiya", [("ひゃく", "hundred"), ("ひゃっかてん", "department store"), ("ひゃくえん", "100 yen")]),
        e("ひゅ", "hyu", "hyoo", "hew", [("ひゅう", "whoosh (sound)"), ("ひゅうひゅう", "whistling wind"), ("ひゅー", "whoosh")]),
        e("ひょ", "hyo", "hyoh", "hyoid", [("ひょう", "table / leopard"), ("ひょうじ", "display"), ("ひょうか", "evaluation")]),

        e("みゃ", "mya", "myah", "meow", [("みゃく", "pulse"), ("みゃん", "meow"), ("みゃー", "meow (variant)")]),
        e("みゅ", "myu", "myoo", "muse", [("みゅーじっく", "music"), ("みゅう", "cute spelling of mew"), ("みゅうと", "mute")]),
        e("みょ", "myo", "myoh", "myopic", [("みょうじ", "family name"), ("みょうが", "Japanese ginger"), ("みょうにち", "day after tomorrow")]),

        e("りゃ", "rya", "ryah", "rye", [("りゃく", "abbreviation"), ("りゃくご", "abbreviation"), ("りゃくれき", "brief history")]),
        e("りゅ", "ryu", "ryoo", "rue", [("りゅう", "dragon / style"), ("りゅうがく", "study abroad"), ("りゅうこう", "trend")]),
        e("りょ", "ryo", "ryoh", "Rio", [("りょこう", "travel"), ("りょう", "dormitory / both"), ("りょうり", "cooking")]),

        e("ぎゃ", "gya", "gyah", "gah!", [("ぎゃく", "reverse"), ("ぎゃくてん", "plot twist"), ("ぎゃー", "scream")]),
        e("ぎゅ", "gyu", "gyoo", "goo", [("ぎゅうにく", "beef"), ("ぎゅっと", "tightly"), ("ぎゅうどん", "beef bowl")]),
        e("ぎょ", "gyo", "gyoh", "gyro", [("ぎょせん", "fishing boat"), ("ぎょぎょう", "fishing industry"), ("ぎょ", "fish (cooking)")]),

        e("じゃ", "ja", "jah", "jar", [("じゃあ", "well then"), ("じゃがいも", "potato"), ("じゃん", "isn't it?")]),
        e("じゅ", "ju", "joo", "jewel", [("じゅう", "ten / gun"), ("じゅぎょう", "class"), ("じゅうしょ", "address")]),
        e("じょ", "jo", "joh", "Joe", [("じょし", "woman"), ("じょうず", "skilled"), ("じょうぶ", "sturdy")]),

        e("びゃ", "bya", "byah", "bye", [("びゃく", "hundred (archaic)"), ("びゃー", "screech"), ("びゃくしん", "suddenly")]),
        e("びゅ", "byu", "byoo", "view", [("びゅー", "beauty"), ("びゅうびゅう", "howling wind"), ("びゅーてぃー", "beauty")]),
        e("びょ", "byo", "byoh", "bio", [("びょういん", "hospital"), ("びょうき", "illness"), ("びょうどう", "equality")]),

        e("ぴゃ", "pya", "pyah", "pew", [("ぴゃん", "bang"), ("ぴゃりぴゃり", "crisp sound"), ("ぴゃー", "squeak")]),
        e("ぴゅ", "pyu", "pyoo", "pew", [("ぴゅー", "pew / spray"), ("ぴゅっ", "pop sound"), ("ぴゅあ", "pure")]),
        e("ぴょ", "pyo", "pyoh", "piano", [("ぴょん", "hop"), ("ぴょこ", "peek out"), ("ぴょんぴょん", "bouncy")]),
    ]

    private static func soundsLikePhrase(_ sound: String, word: String) -> String {
        "\"\(sound)\" as in \"\(word)\""
    }

    private static func e(
        _ kana: String,
        _ romaji: String,
        _ sound: String,
        _ asIn: String,
        _ vocabulary: [(String, String)]
    ) -> KanaDetailItem {
        KanaDetailItem(
            kana: kana,
            romaji: romaji,
            soundsLike: soundsLikePhrase(sound, word: asIn),
            vocabulary: vocabulary.map { KanaVocabExample(japanese: $0.0, meaning: $0.1) }
        )
    }

    // MARK: - Katakana loanword examples

    /// Vocabulary for katakana discovery — loanwords and foreign-origin terms, not hiragana words transliterated.
    private static let katakanaVocabulary: [String: [(String, String)]] = katakanaSeionVocabulary
        .merging(katakanaVoicedVocabulary) { current, _ in current }
        .merging(katakanaYoonVocabulary) { current, _ in current }

    private static let katakanaSeionVocabulary: [String: [(String, String)]] = [
        "ア": [("アイス", "ice cream"), ("アパート", "apartment"), ("アフリカ", "Africa")],
        "イ": [("イギリス", "England"), ("イタリア", "Italy"), ("インク", "ink")],
        "ウ": [("ウイスキー", "whiskey"), ("ウエスト", "west"), ("ウイルス", "virus")],
        "エ": [("エレベーター", "elevator"), ("エンジン", "engine"), ("エプロン", "apron")],
        "オ": [("オレンジ", "orange"), ("オフィス", "office"), ("オーケー", "OK")],

        "カ": [("カメラ", "camera"), ("カフェ", "café"), ("カレー", "curry")],
        "キ": [("キッチン", "kitchen"), ("キーボード", "keyboard"), ("キリン", "giraffe")],
        "ク": [("クラス", "class"), ("クリーム", "cream"), ("クッキー", "cookie")],
        "ケ": [("ケーキ", "cake"), ("ケチャップ", "ketchup"), ("ケータイ", "mobile phone")],
        "コ": [("コーヒー", "coffee"), ("コピー", "copy"), ("コート", "coat")],

        "サ": [("サラダ", "salad"), ("サッカー", "soccer"), ("サンドイッチ", "sandwich")],
        "シ": [("シャツ", "shirt"), ("シェフ", "chef"), ("シーズン", "season")],
        "ス": [("スープ", "soup"), ("スカート", "skirt"), ("スポーツ", "sport")],
        "セ": [("セーター", "sweater"), ("セール", "sale"), ("セロテープ", "cellophane tape")],
        "ソ": [("ソファ", "sofa"), ("ソックス", "socks"), ("ソース", "sauce")],

        "タ": [("タクシー", "taxi"), ("タオル", "towel"), ("タイム", "time")],
        "チ": [("チーズ", "cheese"), ("チケット", "ticket"), ("チョコ", "chocolate")],
        "ツ": [("ツアー", "tour"), ("ツール", "tool"), ("ツイッター", "Twitter")],
        "テ": [("テーブル", "table"), ("テレビ", "TV"), ("テニス", "tennis")],
        "ト": [("トマト", "tomato"), ("トイレ", "toilet"), ("トースト", "toast")],

        "ナ": [("ナイフ", "knife"), ("ナイト", "night"), ("ナプキン", "napkin")],
        "ニ": [("ニュース", "news"), ("ニット", "knit"), ("ニッケル", "nickel")],
        "ヌ": [("ヌードル", "noodle"), ("ヌーボー", "nouveau"), ("ヌー", "new")],
        "ネ": [("ネクタイ", "necktie"), ("ネット", "net / internet"), ("ネイル", "nail")],
        "ノ": [("ノート", "notebook"), ("ノルウェー", "Norway"), ("ノー", "no")],

        "ハ": [("ハンバーガー", "hamburger"), ("ハイキング", "hiking"), ("ハワイ", "Hawaii")],
        "ヒ": [("ヒーター", "heater"), ("ヒーロー", "hero"), ("ヒップ", "hip")],
        "フ": [("フルーツ", "fruit"), ("フライドポテト", "french fries"), ("フロア", "floor")],
        "ヘ": [("ヘリコプター", "helicopter"), ("ヘッドホン", "headphones"), ("ヘルプ", "help")],
        "ホ": [("ホテル", "hotel"), ("ホットドッグ", "hot dog"), ("ホラー", "horror")],

        "マ": [("マスク", "mask"), ("マンガ", "manga"), ("マヨネーズ", "mayonnaise")],
        "ミ": [("ミルク", "milk"), ("ミニ", "mini"), ("ミュージック", "music")],
        "ム": [("ムービー", "movie"), ("ムード", "mood"), ("ムーン", "moon")],
        "メ": [("メニュー", "menu"), ("メロン", "melon"), ("メール", "email")],
        "モ": [("モーター", "motor"), ("モデル", "model"), ("モニター", "monitor")],

        "ヤ": [("ヤンキー", "yankee"), ("ヤード", "yard"), ("ヤクルト", "Yakult")],
        "ユ": [("ユニフォーム", "uniform"), ("ユーロ", "euro"), ("ユーチューブ", "YouTube")],
        "ヨ": [("ヨーロッパ", "Europe"), ("ヨーグルト", "yogurt"), ("ヨット", "yacht")],

        "ラ": [("ラジオ", "radio"), ("ランチ", "lunch"), ("ラーメン", "ramen")],
        "リ": [("リモコン", "remote control"), ("リボン", "ribbon"), ("リサイクル", "recycle")],
        "ル": [("ルール", "rule"), ("ルーム", "room"), ("ルーレット", "roulette")],
        "レ": [("レストラン", "restaurant"), ("レモン", "lemon"), ("レコード", "record")],
        "ロ": [("ロボット", "robot"), ("ローマ", "Rome"), ("ロッカー", "locker")],

        "ワ": [("ワイン", "wine"), ("ワイシャツ", "dress shirt"), ("ワンピース", "one-piece dress")],
        "ヲ": [("ヲタク", "otaku"), ("ヲ", "archaic katakana wo (rare)")],
        "ン": [("ン", "syllable n (usually mid-word)"), ("ンガ", "Nga (name)"), ("ンジュ", "inju (name)")],
    ]

    private static let katakanaVoicedVocabulary: [String: [(String, String)]] = [
        "ガ": [("ガソリン", "gasoline"), ("ガール", "girl"), ("ガラス", "glass")],
        "ギ": [("ギター", "guitar"), ("ギフト", "gift"), ("ギャング", "gang")],
        "グ": [("グラス", "glass / grass"), ("グリーン", "green"), ("グループ", "group")],
        "ゲ": [("ゲーム", "game"), ("ゲスト", "guest"), ("ゲート", "gate")],
        "ゴ": [("ゴルフ", "golf"), ("ゴミ", "trash"), ("ゴールド", "gold")],

        "ザ": [("ザル", "strainer"), ("ザッパ", "Zappa"), ("ザリガニ", "crayfish")],
        "ジ": [("ジーンズ", "jeans"), ("ジャム", "jam"), ("ジョーク", "joke")],
        "ズ": [("ズボン", "pants"), ("ズーム", "zoom"), ("ズッキーニ", "zucchini")],
        "ゼ": [("ゼロ", "zero"), ("ゼリー", "jelly"), ("ゼミ", "seminar")],
        "ゾ": [("ゾンビ", "zombie"), ("ゾーン", "zone"), ("ゾウ", "elephant")],

        "ダ": [("ダンス", "dance"), ("ダイヤ", "diamond"), ("ダイエット", "diet")],
        "ヂ": [("ヂ", "rare ji (same as ジ)")],
        "ヅ": [("ヅ", "rare zu (same as ズ)")],
        "デ": [("デザート", "dessert"), ("デパート", "department store"), ("デート", "date")],
        "ド": [("ドア", "door"), ("ドーナツ", "donut"), ("ドライブ", "drive")],

        "バ": [("バター", "butter"), ("バス", "bus / bath"), ("バナナ", "banana")],
        "ビ": [("ビール", "beer"), ("ビデオ", "video"), ("ビジネス", "business")],
        "ブ": [("ブラウス", "blouse"), ("ブーツ", "boots"), ("ブラジル", "Brazil")],
        "ベ": [("ベッド", "bed"), ("ベルト", "belt"), ("ベーコン", "bacon")],
        "ボ": [("ボール", "ball"), ("ボタン", "button"), ("ボストン", "Boston")],

        "パ": [("パン", "bread"), ("パーティー", "party"), ("パスポート", "passport")],
        "ピ": [("ピアノ", "piano"), ("ピザ", "pizza"), ("ピンク", "pink")],
        "プ": [("プール", "pool"), ("プリン", "pudding"), ("プレゼント", "present")],
        "ペ": [("ペン", "pen"), ("ペット", "pet"), ("ペア", "pair")],
        "ポ": [("ポケット", "pocket"), ("ポスト", "post"), ("ポテト", "potato")],
    ]

    private static let katakanaYoonVocabulary: [String: [(String, String)]] = [
        "キャ": [("キャンプ", "camp"), ("キャプテン", "captain"), ("キャベツ", "cabbage")],
        "キュ": [("キュウリ", "cucumber"), ("キュート", "cute"), ("キュリー", "curry (variant)")],
        "キョ": [("キョウト", "Kyoto (often kanji)"), ("キョロキョロ", "looking around"), ("キョク", "piece (music)")],

        "シャ": [("シャンプー", "shampoo"), ("シャツ", "shirt"), ("シャワー", "shower")],
        "シュ": [("シューズ", "shoes"), ("シュガー", "sugar"), ("シュート", "shoot")],
        "ショ": [("ショップ", "shop"), ("ショート", "short"), ("ショー", "show")],

        "チャ": [("チャンス", "chance"), ("チャーハン", "fried rice"), ("チャイム", "chime")],
        "チュ": [("チューブ", "tube"), ("チューリップ", "tulip"), ("チュー", "chew / kiss sound")],
        "チョ": [("チョコ", "chocolate"), ("チョーク", "chalk"), ("チョッパー", "chopper")],

        "ニャ": [("ニャン", "meow"), ("ニャーニャー", "meow meow"), ("ニャ", "nya")],
        "ニュ": [("ニューヨーク", "New York"), ("ニュース", "news"), ("ニュー", "new")],
        "ニョ": [("ニョロニョロ", "wiggly"), ("ニョ", "nyo")],

        "ヒャ": [("ヒャッハー", "hyahaha"), ("ヒャク", "hundred (variant)"), ("ヒャ", "hya")],
        "ヒュ": [("ヒューマン", "human"), ("ヒュー", "hue / whoosh"), ("ヒューズ", "fuse")],
        "ヒョ": [("ヒョウ", "leopard"), ("ヒョッコリ", "pop out"), ("ヒョ", "hyo")],

        "ミャ": [("ミャオ", "meow (Chinese cat)"), ("ミャ", "mya")],
        "ミュ": [("ミュージック", "music"), ("ミュージカル", "musical"), ("ミュー", "mew")],
        "ミョ": [("ミョウ", "strange (variant)"), ("ミョ", "myo")],

        "リャ": [("リャマ", "llama"), ("リャ", "rya")],
        "リュ": [("リュック", "backpack"), ("リュウ", "dragon (variant)"), ("リュ", "ryu")],
        "リョ": [("リョコウ", "travel (often kanji)"), ("リョ", "ryo")],

        "ギャ": [("ギャル", "gal"), ("ギャング", "gang"), ("ギャップ", "gap")],
        "ギュ": [("ギュッ", "squeeze sound"), ("ギュ", "gyu")],
        "ギョ": [("ギョーザ", "gyoza"), ("ギョ", "gyo")],

        "ジャ": [("ジャケット", "jacket"), ("ジャム", "jam"), ("ジャンプ", "jump")],
        "ジュ": [("ジュース", "juice"), ("ジュニア", "junior"), ("ジュ", "ju")],
        "ジョ": [("ジョギング", "jogging"), ("ジョーク", "joke"), ("ジョ", "jo")],

        "ビャ": [("ビャク", "hundred (archaic)"), ("ビャ", "bya")],
        "ビュ": [("ビューティー", "beauty"), ("ビュッフェ", "buffet"), ("ビュ", "byu")],
        "ビョ": [("ビョウ", "second (variant)"), ("ビョ", "byo")],

        "ピャ": [("ピャー", "squeak"), ("ピャ", "pya")],
        "ピュ": [("ピュア", "pure"), ("ピュー", "pew"), ("ピュ", "pyu")],
        "ピョ": [("ピョンピョン", "bouncy"), ("ピョ", "pyo")],
    ]
}

