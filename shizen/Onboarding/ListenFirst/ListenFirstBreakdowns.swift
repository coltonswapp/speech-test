//
//  ListenFirstBreakdowns.swift
//  shizen
//
//  Hand-written breakdowns for every Japanese line the listen-first flow shows: the office
//  conversation, the textbook/real pairs, each style's phrases, the level samples, Hana's
//  Japanese lines, and the send-off. Onboarding never calls the LLM
//  gateway, so the words, their glosses, and the deeper reading are all written out here.
//  Every word must appear in its line, in order (punctuation left out).
//
//  Needs native-speaker review before it ships, like all content.
//

import Foundation

extension ListenFirstContent {

    private typealias Word = SentenceScrubScript.Word

    /// Keyed by the line's Japanese, exactly as shown.
    static let breakdowns: [String: SentenceScrubScript] = {
        var all: [String: SentenceScrubScript] = [:]
        for (japanese, script) in conversationBreakdowns + phraseBreakdowns + squashBreakdowns + screenBreakdowns {
            assert(all[japanese] == nil, "Two breakdowns for \(japanese)")
            all[japanese] = script
        }
        return all
    }()

    // MARK: - The office conversation

    private static let conversationBreakdowns: [(String, SentenceScrubScript)] = [
        (
            conversation[0].japanese,
            SentenceScrubScript(
                words: [
                    Word("あれ", "Huh?", note: "A surprised \"huh?\", not the あれ that means \"that\"."),
                    Word("まだ", "still"),
                    Word("いた", "were (here)", note: "Past of いる, \"to be\" for people."),
                    Word("の", "softens it into a question", note: "Casual speech asks with の instead of ですか."),
                    Word("何", "what"),
                    Word("して", "doing", note: "て-form of する."),
                    Word("ん", "る, squashed", note: "している → してる → してん: る melts into ん before の."),
                    Word("の", "softens it into a question"),
                ],
                nuance: .init(
                    naturalMeaning: "Oh, you're still here? What are you doing?",
                    impliedMeaning: "Mika is surprised to find Kaito at the office this late. It's a friendly check-in, not a complaint.",
                    notes: "してんの is している squashed twice: している → してる → してん. Ending both questions with の keeps them soft and casual."
                )
            )
        ),
        (
            conversation[1].japanese,
            SentenceScrubScript(
                words: [
                    Word("明日", "tomorrow"),
                    Word("の", "'s, for", note: "Links 明日 to 資料: tomorrow's materials."),
                    Word("資料", "materials, documents"),
                    Word("でも", "but"),
                    Word("ぜんぜん", "(not) at all", note: "Pairs with a negative: ぜんぜん〜ない, \"not at all\"."),
                    Word("わかんない", "don't get it", note: "わからない with ら melted into ん."),
                ],
                nuance: .init(
                    naturalMeaning: "Tomorrow's materials. But I don't get any of it.",
                    impliedMeaning: "Kaito is stuck and a bit worn out, half explaining and half venting.",
                    notes: "The answer drops the verb: 明日の資料 alone is a full reply. わかんない is the everyday way to say わからない."
                )
            )
        ),
        (
            conversation[2].japanese,
            SentenceScrubScript(
                words: [
                    Word("ごめん", "sorry", note: "Casual ごめんなさい."),
                    Word("私", "I, me"),
                    Word("行か", "go", note: "行く in the shape it takes before ない."),
                    Word("なきゃ", "have to", note: "なければならない cut down to its first beat."),
                    Word("終電", "the last train"),
                    Word("なくなっ", "be gone, run out", note: "なくなる, \"to disappear\"."),
                    Word("ちゃう", "(and that would be bad)", note: "Short for てしまう: something happens that you can't undo."),
                ],
                nuance: .init(
                    naturalMeaning: "Sorry, I've gotta go. I'll miss the last train.",
                    impliedMeaning: "She feels a little bad leaving him alone with it, but the last train won't wait.",
                    notes: "行かなきゃ is 行かなければならない with the end cut off. なくなっちゃう is なくなってしまう: the train being gone is the thing she wants to avoid."
                )
            )
        ),
        (
            conversation[3].japanese,
            SentenceScrubScript(
                words: [
                    Word("マジ", "for real, seriously", note: "Slang for 本当."),
                    Word("か", "(surprised question)"),
                    Word("じゃあ", "well then, okay"),
                    Word("また", "again"),
                    Word("明日", "tomorrow"),
                ],
                nuance: .init(
                    naturalMeaning: "Seriously? Okay. See you tomorrow.",
                    impliedMeaning: "Kaito is a little let down to be left on his own, but lets her go without a fuss.",
                    notes: "マジか is a casual \"for real?\" between friends or close coworkers. また明日 is the everyday \"see you tomorrow\"."
                )
            )
        ),
    ]

    // MARK: - Style phrases

    private static let phraseBreakdowns: [(String, SentenceScrubScript)] = [
        // Everything
        (
            "混んでるね。",
            SentenceScrubScript(
                words: [
                    Word("混んでる", "is crowded", note: "混んでいる with the い dropped, as speech almost always does."),
                    Word("ね", "huh, right?", note: "Invites the other person to agree."),
                ],
                nuance: .init(
                    naturalMeaning: "It's really packed, huh.",
                    impliedMeaning: "Small talk: noticing something together and inviting a nod.",
                    notes: "Textbook: 混んでいますね. Dropping い and です is what makes it sound like a friend talking."
                )
            )
        ),
        (
            "いつものでいい？",
            SentenceScrubScript(
                words: [
                    Word("いつもの", "the usual", note: "\"Always\" + の: the always-one."),
                    Word("で", "as, with"),
                    Word("いい", "good, okay"),
                ],
                nuance: .init(
                    naturalMeaning: "The usual?",
                    impliedMeaning: "Said by someone who already knows your order: a friend, or the staff at your regular café.",
                    notes: "〜でいい？ asks \"will … do?\". いつもの turns \"always\" into \"the usual thing\"."
                )
            )
        ),
        (
            "ちょっと待ってて。",
            SentenceScrubScript(
                words: [
                    Word("ちょっと", "a sec, a little"),
                    Word("待って", "wait"),
                    Word("て", "keep (waiting)", note: "From 待っていて with the い dropped."),
                ],
                nuance: .init(
                    naturalMeaning: "Hang on a sec.",
                    impliedMeaning: "\"Stay right there, I'll be back\", not just \"pause\".",
                    notes: "待ってて is 待っていて squashed. The extra て means \"keep waiting\". Textbook: ちょっと待っていてください."
                )
            )
        ),
        // Casual
        (
            "今日、暇？",
            SentenceScrubScript(
                words: [
                    Word("今日", "today"),
                    Word("暇", "free, not busy"),
                ],
                nuance: .init(
                    naturalMeaning: "Free today?",
                    impliedMeaning: "Usually the lead-in to an invitation.",
                    notes: "Casual speech drops は and ですか. A rising tone alone makes it a question. Textbook: 今日は暇ですか？"
                )
            )
        ),
        (
            "それ、マジ？",
            SentenceScrubScript(
                words: [
                    Word("それ", "that"),
                    Word("マジ", "for real", note: "Slang for 本当."),
                ],
                nuance: .init(
                    naturalMeaning: "Seriously?",
                    impliedMeaning: "Surprise or disbelief at what you just heard.",
                    notes: "Textbook would be それは本当ですか？ Among friends, two words do it."
                )
            )
        ),
        (
            "行こ行こ！",
            SentenceScrubScript(
                words: [
                    Word("行こ", "let's go", note: "行こう with the long う cut off."),
                    Word("行こ", "let's go"),
                ],
                nuance: .init(
                    naturalMeaning: "Let's go, let's go!",
                    impliedMeaning: "Excited and eager: come on, let's do it.",
                    notes: "Saying it twice adds energy. Textbook: 行きましょう."
                )
            )
        ),
        // College
        (
            "やばっ、寝坊した！",
            SentenceScrubScript(
                words: [
                    Word("やばっ", "oh no", note: "やばい clipped short for a sudden reaction."),
                    Word("寝坊", "oversleeping"),
                    Word("した", "did", note: "Past of する."),
                ],
                nuance: .init(
                    naturalMeaning: "Crap, I overslept!",
                    impliedMeaning: "Panicked: they're probably already late.",
                    notes: "Textbook: 寝坊してしまいました. やばい covers anything from \"uh-oh\" to \"amazing\"; here it's \"uh-oh\"."
                )
            )
        ),
        (
            "終電行っちゃった。",
            SentenceScrubScript(
                words: [
                    Word("終電", "the last train"),
                    Word("行っ", "went", note: "行く, \"to go\"."),
                    Word("ちゃった", "(and it's too late)", note: "てしまった squashed: it happened and can't be undone."),
                ],
                nuance: .init(
                    naturalMeaning: "The last train's gone.",
                    impliedMeaning: "They're stranded: a taxi, a long walk, or a night out.",
                    notes: "Textbook: 終電が行ってしまった. Speech drops が and squashes てしまった to ちゃった."
                )
            )
        ),
        (
            "テスト、ガチで無理。",
            SentenceScrubScript(
                words: [
                    Word("テスト", "test, exam"),
                    Word("ガチで", "seriously, for real", note: "Slang."),
                    Word("無理", "impossible, no way"),
                ],
                nuance: .init(
                    naturalMeaning: "This test is seriously impossible.",
                    impliedMeaning: "Complaining, and probably exaggerating.",
                    notes: "ガチで is younger slang for 本当に. 無理 is the everyday \"no way, can't\"."
                )
            )
        ),
        // Polite
        (
            "ご確認いただけますでしょうか。",
            SentenceScrubScript(
                words: [
                    Word("ご確認", "checking", note: "確認 with the polite ご."),
                    Word("いただけます", "could I receive", note: "Humble: \"could I have you (check)\"."),
                    Word("でしょうか", "would it be…?", note: "A softer ですか."),
                ],
                nuance: .init(
                    naturalMeaning: "Could you please take a look?",
                    impliedMeaning: "A careful request at work, often to a client or a boss.",
                    notes: "Literally \"might I be able to receive your checking?\" Each polite layer makes the request softer."
                )
            )
        ),
        (
            "恐れ入りますが…",
            SentenceScrubScript(
                words: [
                    Word("恐れ入ります", "I'm sorry to trouble you", note: "Humble and formal."),
                    Word("が", "but…"),
                ],
                nuance: .init(
                    naturalMeaning: "I'm sorry to trouble you, but…",
                    impliedMeaning: "A cushion before a request or an interruption, common in shops and offices.",
                    notes: "It often trails off: everyone knows a request is coming."
                )
            )
        ),
        (
            "承知いたしました。",
            SentenceScrubScript(
                words: [
                    Word("承知", "understanding, noted"),
                    Word("いたしました", "did", note: "Humble form of しました."),
                ],
                nuance: .init(
                    naturalMeaning: "Understood.",
                    impliedMeaning: "Formal and respectful, and it promises you'll take care of it.",
                    notes: "The humble version of わかりました, for customers and bosses."
                )
            )
        ),
        // Travel
        (
            "お待たせいたしました。",
            SentenceScrubScript(
                words: [
                    Word("お待たせ", "making you wait"),
                    Word("いたしました", "did", note: "Humble form of しました."),
                ],
                nuance: .init(
                    naturalMeaning: "Thanks for waiting.",
                    impliedMeaning: "Staff say it as they bring your order or come back to you.",
                    notes: "Literally \"I have made you wait.\" You'll hear it at almost every counter."
                )
            )
        ),
        (
            "こちらでお召し上がりですか？",
            SentenceScrubScript(
                words: [
                    Word("こちら", "here", note: "Polite ここ."),
                    Word("で", "at"),
                    Word("お召し上がり", "eating", note: "Honorific 食べる, used for customers."),
                    Word("ですか", "is it?"),
                ],
                nuance: .init(
                    naturalMeaning: "For here?",
                    impliedMeaning: "The \"for here or to go?\" question at cafés and fast food counters.",
                    notes: "The answer is usually はい or 持ち帰りで (to go)."
                )
            )
        ),
        (
            "少々お待ちください。",
            SentenceScrubScript(
                words: [
                    Word("少々", "a moment", note: "Formal ちょっと."),
                    Word("お待ち", "waiting", note: "Polite 待つ."),
                    Word("ください", "please"),
                ],
                nuance: .init(
                    naturalMeaning: "One moment, please.",
                    impliedMeaning: "Staff stepping away briefly to check something.",
                    notes: "A fixed phrase. Casual would be ちょっと待って."
                )
            )
        ),
        // Anime
        (
            "絶対、負けないからな！",
            SentenceScrubScript(
                words: [
                    Word("絶対", "definitely, no matter what"),
                    Word("負けない", "won't lose"),
                    Word("から", "I'm telling you", note: "Here から isn't \"because\"; it's insistence."),
                    Word("な", "(rough emphasis)"),
                ],
                nuance: .init(
                    naturalMeaning: "I'm not going to lose, got it?",
                    impliedMeaning: "A challenge, or a promise to a rival.",
                    notes: "からな adds a rough \"you hear me?\". Common in anime, too strong for most real conversations."
                )
            )
        ),
        (
            "なんでだよ！",
            SentenceScrubScript(
                words: [
                    Word("なんで", "why"),
                    Word("だ", "is"),
                    Word("よ", "(emphasis)"),
                ],
                nuance: .init(
                    naturalMeaning: "Why, though?!",
                    impliedMeaning: "A frustrated protest: that makes no sense!",
                    notes: "だよ adds force. Casual and a bit rough."
                )
            )
        ),
        (
            "任せとけ！",
            SentenceScrubScript(
                words: [
                    Word("任せ", "leave (it) to", note: "任せる."),
                    Word("とけ", "do it, and that's that", note: "ておけ squashed: 任せておけ → 任せとけ."),
                ],
                nuance: .init(
                    naturalMeaning: "Leave it to me!",
                    impliedMeaning: "Confident, a little cocky.",
                    notes: "A blunt command form. Textbook: 任せておけ, or politely 任せてください."
                )
            )
        ),
    ]

    // MARK: - Textbooks vs. real life

    private static let squashBreakdowns: [(String, SentenceScrubScript)] = [
        (
            "わかりません。",
            SentenceScrubScript(
                words: [
                    Word("わかり", "understand", note: "わかる, usually written 分かる."),
                    Word("ません", "don't", note: "Polite negative."),
                ],
                nuance: .init(
                    naturalMeaning: "I don't understand.",
                    impliedMeaning: "Polite and complete, the way a textbook or a stranger says it.",
                    notes: "Among friends this nearly always comes out as わかんない."
                )
            )
        ),
        (
            "わからない。",
            SentenceScrubScript(
                words: [
                    Word("わから", "understand", note: "わかる before ない."),
                    Word("ない", "don't", note: "Plain negative: ません without the politeness."),
                ],
                nuance: .init(
                    naturalMeaning: "I don't understand.",
                    impliedMeaning: "Plain and complete. Fine with friends, if a little careful.",
                    notes: "Same words as わかりません, just not polite. Say it fast and ら melts into ん: わかんない."
                )
            )
        ),
        (
            "わかんない。",
            SentenceScrubScript(
                words: [
                    Word("わかん", "understand", note: "わから, with ら melted into ん."),
                    Word("ない", "don't", note: "Plain negative."),
                ],
                nuance: .init(
                    naturalMeaning: "I don't get it.",
                    impliedMeaning: "Casual and a little helpless.",
                    notes: "わからない → わかんない. A ら or る before a ん-friendly sound often turns into ん in speech."
                )
            )
        ),
        (
            "何をしているのですか？",
            SentenceScrubScript(
                words: [
                    Word("何", "what"),
                    Word("を", "(object marker)"),
                    Word("して", "doing", note: "て-form of する."),
                    Word("いる", "(ongoing)", note: "している: \"is doing\"."),
                    Word("のですか", "(polite question)", note: "の + ですか: explaining, politely."),
                ],
                nuance: .init(
                    naturalMeaning: "What are you doing?",
                    impliedMeaning: "Correct and polite, but stiff. Nobody talks to a friend like this.",
                    notes: "Every particle and ending is spelled out. Speech drops を, い, and です."
                )
            )
        ),
        (
            "何をしているの？",
            SentenceScrubScript(
                words: [
                    Word("何", "what"),
                    Word("を", "(object marker)"),
                    Word("して", "doing", note: "て-form of する."),
                    Word("いる", "(ongoing)", note: "している: \"is doing\"."),
                    Word("の", "(casual question)", note: "のですか without the ですか."),
                ],
                nuance: .init(
                    naturalMeaning: "What are you doing?",
                    impliedMeaning: "Casual, but every sound is still there.",
                    notes: "The politeness is gone. Speech then drops を and い: 何してんの？"
                )
            )
        ),
        (
            "何してんの？",
            SentenceScrubScript(
                words: [
                    Word("何", "what"),
                    Word("して", "doing", note: "を is gone: you can guess it."),
                    Word("ん", "る, squashed", note: "している → してる → してん."),
                    Word("の", "(casual question)"),
                ],
                nuance: .init(
                    naturalMeaning: "What are you up to?",
                    impliedMeaning: "Friendly and curious.",
                    notes: "Half the sounds of 何をしているのですか, same meaning."
                )
            )
        ),
        (
            "行かなければなりません。",
            SentenceScrubScript(
                words: [
                    Word("行か", "go", note: "行く before ない."),
                    Word("なければ", "if (I) don't"),
                    Word("なりません", "it won't do", note: "Polite: \"it won't do if I don't go\"."),
                ],
                nuance: .init(
                    naturalMeaning: "I must go.",
                    impliedMeaning: "Formal: an announcement more than a goodbye.",
                    notes: "Literally \"if I don't go, it won't do\". Speech cuts it down to 行かなきゃ."
                )
            )
        ),
        (
            "行かなければならない。",
            SentenceScrubScript(
                words: [
                    Word("行か", "go", note: "行く before ない."),
                    Word("なければ", "if (I) don't"),
                    Word("ならない", "it won't do", note: "なりません without the politeness."),
                ],
                nuance: .init(
                    naturalMeaning: "I have to go.",
                    impliedMeaning: "Plain but still long. You'd write it more than say it.",
                    notes: "Speech keeps the start and cuts the rest: なければ → なきゃ, and ならない is left for you to fill in."
                )
            )
        ),
        (
            "行かなきゃ。",
            SentenceScrubScript(
                words: [
                    Word("行か", "go"),
                    Word("なきゃ", "have to", note: "なければ squashed; the rest is dropped."),
                ],
                nuance: .init(
                    naturalMeaning: "I've gotta go.",
                    impliedMeaning: "Casual, often said while already getting up.",
                    notes: "なきゃ is なければ with the ending cut. Listeners fill in ならない."
                )
            )
        ),
    ]

    // MARK: - Hana, the level samples, and the send-off

    private static let screenBreakdowns: [(String, SentenceScrubScript)] = [
        // Level samples
        (
            "こんにちは！",
            SentenceScrubScript(
                words: [Word("こんにちは", "hello", note: "The は is said わ.")],
                nuance: .init(
                    naturalMeaning: "Hello!",
                    impliedMeaning: "A friendly daytime greeting.",
                    notes: "Fine with almost anyone. Friends often skip it for a quick やあ or おはよう."
                )
            )
        ),
        (
            "おなまえは なんですか？",
            SentenceScrubScript(
                words: [
                    Word("おなまえ", "(your) name", note: "名前 with the polite お."),
                    Word("は", "(topic)", note: "Said わ."),
                    Word("なん", "what", note: "何 before です."),
                    Word("ですか", "is it?"),
                ],
                nuance: .init(
                    naturalMeaning: "What's your name?",
                    impliedMeaning: "Polite, for someone you've just met.",
                    notes: "The polite お makes it about their name, not yours."
                )
            )
        ),
        (
            "週末は何をしていましたか？",
            SentenceScrubScript(
                words: [
                    Word("週末", "weekend"),
                    Word("は", "(topic)"),
                    Word("何", "what"),
                    Word("を", "(object marker)"),
                    Word("して", "doing"),
                    Word("いましたか", "were (you)?", note: "Polite past of いる, as a question."),
                ],
                nuance: .init(
                    naturalMeaning: "What did you do this weekend?",
                    impliedMeaning: "Polite small talk, like with a coworker on Monday.",
                    notes: "Every piece is there. The casual version is 週末なにしてた？"
                )
            )
        ),
        (
            "週末なにしてた？めっちゃ天気よかったじゃん。",
            SentenceScrubScript(
                words: [
                    Word("週末", "weekend", note: "は is dropped."),
                    Word("なに", "what", note: "を is dropped."),
                    Word("して", "doing"),
                    Word("た", "were", note: "していた with the い dropped."),
                    Word("めっちゃ", "super, really", note: "Casual, originally from Kansai."),
                    Word("天気", "weather"),
                    Word("よかった", "was good", note: "Past of いい."),
                    Word("じゃん", "right?, you know", note: "Casual じゃないか: pointing out something obvious."),
                ],
                nuance: .init(
                    naturalMeaning: "What'd you get up to this weekend? The weather was amazing.",
                    impliedMeaning: "Friendly catch-up between friends.",
                    notes: "Particles drop, していた squashes to してた, and じゃん asks you to agree."
                )
            )
        ),
        // The plan
        (
            "うわー！8週間でこんなに聞けるの？",
            SentenceScrubScript(
                words: [
                    Word("うわー", "whoa"),
                    Word("8週間", "eight weeks"),
                    Word("で", "in, within"),
                    Word("こんなに", "this much"),
                    Word("聞ける", "can hear", note: "Potential form of 聞く."),
                    Word("の", "(surprised question)"),
                ],
                nuance: .init(
                    naturalMeaning: "Whoa, you'll hear this much in eight weeks?",
                    impliedMeaning: "Hana is genuinely impressed.",
                    notes: "Ending with の makes it a soft, surprised question."
                )
            )
        ),
        (
            "毎日ちょっとずつで大丈夫。",
            SentenceScrubScript(
                words: [
                    Word("毎日", "every day"),
                    Word("ちょっとずつ", "a little at a time"),
                    Word("で", "with, as"),
                    Word("大丈夫", "fine, okay"),
                ],
                nuance: .init(
                    naturalMeaning: "A little every day is all it takes.",
                    impliedMeaning: "Reassurance: you don't need big sessions.",
                    notes: "〜で大丈夫 means \"… is enough, … is fine\"."
                )
            )
        ),
        (
            "頑張ろうね！",
            SentenceScrubScript(
                words: [
                    Word("頑張ろう", "let's do our best", note: "Volitional of 頑張る."),
                    Word("ね", "okay?, together"),
                ],
                nuance: .init(
                    naturalMeaning: "Let's do this!",
                    impliedMeaning: "Warm encouragement, with Hana in it alongside you.",
                    notes: "ね turns \"let's try hard\" into \"let's try hard together, yeah?\""
                )
            )
        ),
        (
            "最初のレッスンだよ。スワイプして見てみて！",
            SentenceScrubScript(
                words: [
                    Word("最初", "first"),
                    Word("の", "'s, of"),
                    Word("レッスン", "lesson"),
                    Word("だよ", "is (, you know)", note: "だ + よ: telling you something."),
                    Word("スワイプ", "swipe"),
                    Word("して", "do", note: "スワイプする, \"to swipe\"."),
                    Word("見て", "look"),
                    Word("みて", "try", note: "〜てみて: \"give it a try\"."),
                ],
                nuance: .init(
                    naturalMeaning: "Here's your first lesson. Swipe through it!",
                    impliedMeaning: "An invitation to have a look around.",
                    notes: "見てみて is \"try looking\": a gentle way to ask."
                )
            )
        ),
        // The promise
        (
            "ちょっと待って。",
            SentenceScrubScript(
                words: [
                    Word("ちょっと", "a sec, a little"),
                    Word("待って", "wait", note: "て-form as a casual request."),
                ],
                nuance: .init(
                    naturalMeaning: "Hold on a sec.",
                    impliedMeaning: "Hana has something to say before you go on.",
                    notes: "The polite version is ちょっと待ってください."
                )
            )
        ),
        (
            "正直に言うね。途中でやめる人は手伝わないよ。",
            SentenceScrubScript(
                words: [
                    Word("正直に", "honestly"),
                    Word("言う", "say"),
                    Word("ね", "(softener)"),
                    Word("途中で", "partway, in the middle"),
                    Word("やめる", "quit"),
                    Word("人", "person, people"),
                    Word("は", "(topic)"),
                    Word("手伝わない", "won't help", note: "Negative of 手伝う."),
                    Word("よ", "(telling you)"),
                ],
                nuance: .init(
                    naturalMeaning: "I'll be honest: I don't help quitters.",
                    impliedMeaning: "Playfully stern, setting up the promise.",
                    notes: "途中でやめる人 is \"people who quit partway\": the whole phrase describes 人."
                )
            )
        ),
        (
            "最初のレッスン、最後までやるって約束できる？",
            SentenceScrubScript(
                words: [
                    Word("最初", "first"),
                    Word("の", "'s, of"),
                    Word("レッスン", "lesson"),
                    Word("最後", "the end"),
                    Word("まで", "until"),
                    Word("やる", "do"),
                    Word("って", "that", note: "Casual と, quoting what you'd promise."),
                    Word("約束", "promise"),
                    Word("できる", "can (you)"),
                ],
                nuance: .init(
                    naturalMeaning: "Can you promise to finish your first lesson?",
                    impliedMeaning: "A friendly but real ask.",
                    notes: "最後までやる is \"see it through to the end\". って quotes the promise."
                )
            )
        ),
        (
            "約束だよ！",
            SentenceScrubScript(
                words: [
                    Word("約束", "promise"),
                    Word("だよ", "it is (, okay?)"),
                ],
                nuance: .init(
                    naturalMeaning: "It's a promise!",
                    impliedMeaning: "Sealing the deal, with a smile.",
                    notes: "だよ adds \"I'm holding you to it\"."
                )
            )
        ),
        (
            "じゃあ、さっそく始めよう！",
            SentenceScrubScript(
                words: [
                    Word("じゃあ", "well then"),
                    Word("さっそく", "right away"),
                    Word("始めよう", "let's start", note: "Volitional of 始める."),
                ],
                nuance: .init(
                    naturalMeaning: "Then let's get started!",
                    impliedMeaning: "Eager to begin.",
                    notes: "さっそく means \"without wasting any time\"."
                )
            )
        ),
        // The send-off
        (
            "聞いてみよう！",
            SentenceScrubScript(
                words: [
                    Word("聞いて", "listen"),
                    Word("みよう", "let's try", note: "〜てみよう: \"let's give it a go\"."),
                ],
                nuance: .init(
                    naturalMeaning: "Let's have a listen!",
                    impliedMeaning: "An invitation to start.",
                    notes: "てみる means \"try doing\"; みよう makes it \"let's\"."
                )
            )
        ),
        (
            "また聞きに来てね！",
            SentenceScrubScript(
                words: [
                    Word("また", "again"),
                    Word("聞き", "listen", note: "Stem of 聞く, before に."),
                    Word("に", "to (do)", note: "Purpose: come to listen."),
                    Word("来て", "come"),
                    Word("ね", "okay?"),
                ],
                nuance: .init(
                    naturalMeaning: "Come back and listen again soon!",
                    impliedMeaning: "A warm goodbye.",
                    notes: "Stem + に + 来る: \"come (in order) to …\"."
                )
            )
        ),
        (
            "じゃあ、またね！",
            SentenceScrubScript(
                words: [
                    Word("じゃあ", "well then"),
                    Word("また", "again"),
                    Word("ね", "(friendly)"),
                ],
                nuance: .init(
                    naturalMeaning: "See you!",
                    impliedMeaning: "The everyday goodbye between friends.",
                    notes: "またね is short for また会おうね, \"let's meet again\"."
                )
            )
        ),
        (
            "終電、逃さないでね！",
            SentenceScrubScript(
                words: [
                    Word("終電", "the last train"),
                    Word("逃さないで", "don't miss", note: "Negative request of 逃す."),
                    Word("ね", "okay?"),
                ],
                nuance: .init(
                    naturalMeaning: "Don't miss the last train!",
                    impliedMeaning: "A friendly, teasing goodbye after a late night.",
                    notes: "〜ないで is \"please don't …\"."
                )
            )
        ),
        (
            "お待ちしております。",
            SentenceScrubScript(
                words: [
                    Word("お待ち", "waiting", note: "Humble 待つ."),
                    Word("して", "doing"),
                    Word("おります", "am (doing)", note: "Humble いる."),
                ],
                nuance: .init(
                    naturalMeaning: "We look forward to seeing you.",
                    impliedMeaning: "What a shop or hotel says to a customer.",
                    notes: "Literally \"I am humbly waiting\". Very formal."
                )
            )
        ),
        (
            "いってらっしゃい！",
            SentenceScrubScript(
                words: [Word("いってらっしゃい", "see you, have a good one", note: "Literally \"go and come back\".")],
                nuance: .init(
                    naturalMeaning: "Have a great trip!",
                    impliedMeaning: "Said to someone heading out, who's expected back.",
                    notes: "The answer is いってきます, \"I'm off\"."
                )
            )
        ),
        (
            "屋上で待ってるね！",
            SentenceScrubScript(
                words: [
                    Word("屋上", "the rooftop"),
                    Word("で", "at"),
                    Word("待ってる", "will be waiting", note: "待っている with the い dropped."),
                    Word("ね", "okay?"),
                ],
                nuance: .init(
                    naturalMeaning: "Meet me on the rooftop!",
                    impliedMeaning: "A classic anime school scene: something important is about to happen.",
                    notes: "待ってる can mean \"am waiting\" or \"will be waiting\"."
                )
            )
        ),
    ]
}
