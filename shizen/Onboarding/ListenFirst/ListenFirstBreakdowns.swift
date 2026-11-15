//
//  ListenFirstBreakdowns.swift
//  shizen
//
//  Hand-written breakdowns for every Japanese line the listen-first flow shows: the drinks
//  conversation, the textbook/real pairs, the level samples, Hana's
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
        for (japanese, script) in conversationBreakdowns + squashBreakdowns + screenBreakdowns {
            assert(all[japanese] == nil, "Two breakdowns for \(japanese)")
            all[japanese] = script
        }
        return all
    }()

    // MARK: - The drinks conversation

    private static let conversationBreakdowns: [(String, SentenceScrubScript)] = [
        (
            conversation[0].japanese,
            SentenceScrubScript(
                words: [
                    Word("何", "what"),
                    Word("して", "doing", note: "て-form of する."),
                    Word("ん", "る, squashed", note: "している → してる → してん: る melts into ん before の."),
                    Word("の", "softens it into a question", note: "Casual speech asks with の instead of ですか."),
                ],
                nuance: .init(
                    naturalMeaning: "What are you doing?",
                    impliedMeaning: "Mika notices Kaito looking stuck on something and checks in.",
                    notes: "してんの is している squashed twice: している → してる → してん. Ending on の keeps it soft and casual."
                )
            )
        ),
        (
            conversation[1].japanese,
            SentenceScrubScript(
                words: [
                    Word("明日", "tomorrow"),
                    Word("の", "'s", note: "Links 明日 to 飲み会: tomorrow's drinks."),
                    Word("飲み会", "drinks, a drinking party", note: "A group night out, often with classmates or coworkers."),
                    Word("行く", "go"),
                    Word("か", "whether", note: "Turns 行く into \"whether to go\"."),
                    Word("迷って", "unsure, torn", note: "迷う, \"to be lost\" or \"to hesitate\"."),
                    Word("る", "(ongoing)", note: "迷っている with い dropped: 迷ってる."),
                ],
                nuance: .init(
                    naturalMeaning: "I can't decide if I'm going to drinks tomorrow.",
                    impliedMeaning: "Kaito is leaning toward staying home and half wants someone to talk him out of it.",
                    notes: "The に after 飲み会 is dropped, and 迷っている loses its い: 迷ってる. Both are normal in speech."
                )
            )
        ),
        (
            conversation[2].japanese,
            SentenceScrubScript(
                words: [
                    Word("え", "What?", note: "A quick, surprised \"huh?\"."),
                    Word("行か", "go", note: "行く in the shape it takes before ない."),
                    Word("なきゃ", "have to", note: "なければならない cut down to its first beat."),
                    Word("サキ", "Saki", note: "A name."),
                    Word("ちゃん", "(friendly name ending)", note: "Like さん, but warm and casual."),
                    Word("来る", "come"),
                    Word("よ", "(you should know)", note: "Tells someone something new."),
                ],
                nuance: .init(
                    naturalMeaning: "What? You have to go! Saki's coming.",
                    impliedMeaning: "Mika knows Kaito likes Saki, and she's using it.",
                    notes: "行かなきゃ isn't only \"I have to leave\". Here it pushes Kaito: you have to go. よ hands him news he didn't have."
                )
            )
        ),
        (
            conversation[3].japanese,
            SentenceScrubScript(
                words: [
                    Word("マジ", "for real, seriously", note: "Slang for 本当."),
                    Word("で", "(for real?)", note: "マジで: \"seriously?\""),
                    Word("何", "what"),
                    Word("着れば", "if (I) wear", note: "着る, \"to wear\", in its \"if\" form."),
                    Word("いい", "good"),
                    Word("か", "whether"),
                    Word("わかんない", "don't know", note: "わからない with ら melted into ん."),
                ],
                nuance: .init(
                    naturalMeaning: "...Seriously? I don't know what to wear.",
                    impliedMeaning: "He's going now. The question is settled, and the panic has already started.",
                    notes: "何着ればいいか is \"what would be good to wear\". わかんない is the everyday way to say わからない."
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
