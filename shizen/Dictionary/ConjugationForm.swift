//
//  ConjugationForm.swift
//  shizen
//
//  Names the form of a tapped verb or adjective (聞きました → polite past of 聞く).
//  Forms are rebuilt from the dictionary form and its JMdict class, then matched
//  exactly against the tapped text, so an ending that only looks like a suffix
//  (覚ました is the plain past of 覚ます, not 〜ました) is never mislabeled. No match → nil.
//
//  Pure Foundation so ConjugationTests can compile this file directly (symlinked there).
//

import Foundation

enum ConjugationForm {

    struct Match: Equatable {
        /// Short label, e.g. "Polite past".
        let name: String
        /// One or two short sentences, e.g. "Past tense, said politely (〜ました)."
        let detail: String
    }

    enum WordClass: Equatable {
        case godan(GodanKind)
        case ichidan
        /// 来る / くる.
        case kuru
        /// Lemma written with する (する, 愛する, 勉強する).
        case suru
        /// Noun that takes する (勉強 → 勉強する).
        case suruNoun
        case iAdjective
    }

    enum GodanKind: Equatable {
        case regular
        /// 行く: te/ta are 行って / 行った.
        case iku
        /// なさる, いらっしゃる, くださる: masu stem and imperative end in い.
        case aru
        /// ある: negative is ない.
        case aruIrregular
    }

    /// The form `surface` takes relative to `lemma`, or nil when it is not a verb/adjective
    /// form we can rebuild. `lemmaReading` lets kana surfaces (ききました) match a kanji lemma.
    static func identify(
        surface: String,
        lemma: String,
        lemmaReading: String? = nil,
        tags: String?
    ) -> Match? {
        let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemma = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        // 為る is tagged vs-i but is not spelled 〜する; its reading する carries the class.
        let readingSpelling = lemmaReading?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty, !lemma.isEmpty,
              let wordClass = wordClass(lemma: lemma, tags: tags)
                ?? readingSpelling.flatMap({ wordClass(lemma: $0, tags: tags) })
        else { return nil }

        var spellings = [lemma]
        if let reading = lemmaReading?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reading.isEmpty, reading != lemma {
            spellings.append(reading)
        }
        for spelling in spellings {
            // A reading spelled in kana must still carry the same class (くる for 来る).
            guard let cls = spelling == lemma ? wordClass : readingClass(wordClass, reading: spelling) else {
                continue
            }
            if let match = forms(of: spelling, as: cls).first(where: { $0.text == surface })?.match {
                return match
            }
        }
        return nil
    }

    /// Kana reading of a conjugated `surface` (来ました → きました), built by matching it to the
    /// same form of `lemma` and taking that form of `lemmaReading`. A kana surface that is
    /// already a form of the reading comes back as is. Nil when no form matches.
    static func reading(
        surface: String,
        lemma: String,
        lemmaReading: String,
        tags: String?
    ) -> String? {
        let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemma = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemmaReading = lemmaReading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty, !lemma.isEmpty, !lemmaReading.isEmpty,
              let cls = wordClass(lemma: lemma, tags: tags),
              let readingCls = readingClass(cls, reading: lemmaReading)
        else { return nil }
        let readingForms = forms(of: lemmaReading, as: readingCls)
        if readingForms.contains(where: { $0.text == surface }) {
            return surface
        }
        // Both lists are built by the same steps, so index i is the same form in each.
        let writtenForms = forms(of: lemma, as: cls)
        guard writtenForms.count == readingForms.count,
              let index = writtenForms.firstIndex(where: { $0.text == surface })
        else { return nil }
        return readingForms[index].text
    }

    /// Verb or adjective class from JMdict tags. The bundled DB mixes codes (v5k, v1, adj-i)
    /// with truncated spelled-out labels ("Kuru verb - special", "Godan verb - Iku/Yuk").
    static func wordClass(lemma: String, tags: String?) -> WordClass? {
        guard let tags, !tags.isEmpty else { return nil }
        let codes = Set(tags.split(separator: " ").map(String.init))
        let lower = tags.lowercased()

        if codes.contains("vk") || lower.contains("kuru verb") {
            return lemma.hasSuffix("来る") || lemma.hasSuffix("くる") ? .kuru : nil
        }
        if codes.contains("vs-i") || codes.contains("vs-s") || lower.contains("suru verb") {
            return lemma.hasSuffix("する") ? .suru : nil
        }
        // ずる verbs (信ずる) and archaic nidan classes are rare; leave them unlabeled.
        if codes.contains("vz") || lower.contains("zuru") || lower.contains("nidan") {
            return nil
        }
        if codes.contains(where: { $0.hasPrefix("v1") }) || lower.contains("ichidan verb") {
            return lemma.hasSuffix("る") ? .ichidan : nil
        }
        if codes.contains("v5k-s") || lower.contains("iku/yuk") {
            return lemma.hasSuffix("く") ? .godan(.iku) : nil
        }
        if codes.contains("v5aru") || lower.contains("-aru sp") {
            return lemma.hasSuffix("る") ? .godan(.aru) : nil
        }
        if codes.contains("v5r-i") {
            return lemma.hasSuffix("る") ? .godan(.aruIrregular) : nil
        }
        if codes.contains(where: { $0.hasPrefix("v5") }) || lower.contains("godan verb") {
            guard let last = lemma.last, godanRows[last] != nil else { return nil }
            return .godan(.regular)
        }
        if codes.contains("adj-i") || codes.contains("adj-ix") || lower.contains("keiyoushi") {
            return lemma.hasSuffix("い") ? .iAdjective : nil
        }
        if codes.contains("vs") || lower.contains("noun or participle w") {
            return lemma.hasSuffix("する") ? .suru : .suruNoun
        }
        return nil
    }

    // MARK: - Form tables

    private struct Form {
        let text: String
        let match: Match
    }

    private static func readingClass(_ cls: WordClass, reading: String) -> WordClass? {
        switch cls {
        case .kuru: reading.hasSuffix("くる") ? .kuru : nil
        case .suru: reading.hasSuffix("する") ? .suru : nil
        case .ichidan: reading.hasSuffix("る") ? .ichidan : nil
        case .iAdjective: reading.hasSuffix("い") ? .iAdjective : nil
        case .godan:
            reading.last.map { godanRows[$0] != nil } == true ? cls : nil
        case .suruNoun: .suruNoun
        }
    }

    private static func forms(of lemma: String, as cls: WordClass) -> [Form] {
        if cls == .iAdjective {
            return adjectiveForms(lemma)
        }
        guard let verb = verb(lemma, as: cls) else { return [] }
        var out: [Form] = []
        if cls == .suruNoun {
            out.append(Form(text: lemma + "する", match: Match(
                name: "する verb",
                detail: "The noun used as a verb with する, plain non-past."
            )))
        }
        out += verbForms(verb, extended: true)
        for derived in derivedVerbs(lemma, as: cls) {
            guard let root = ichidanVerb(derived.dictionary) else { continue }
            for form in verbForms(root, extended: false) {
                let isBase = form.text == derived.dictionary
                out.append(Form(text: form.text, match: Match(
                    name: isBase ? derived.name : "\(derived.name), \(form.match.name.lowercased())",
                    detail: isBase ? derived.detail : "\(derived.detail) \(form.match.detail)"
                )))
            }
        }
        return out
    }

    /// Stems one verb needs to build its forms.
    private struct Verb {
        let dictionary: String
        let masuStem: String
        /// Text before ない (聞か). Empty for ある, whose negative is ない.
        let negativeStem: String
        let te: String
        let ta: String
        let conditional: String
        let volitional: String
        let imperative: String?
    }

    private struct Derived {
        let dictionary: String
        let name: String
        let detail: String
    }

    private static let godanRows: [Character: (a: String, i: String, e: String, o: String, te: String, ta: String)] = [
        "う": ("わ", "い", "え", "お", "って", "った"),
        "く": ("か", "き", "け", "こ", "いて", "いた"),
        "ぐ": ("が", "ぎ", "げ", "ご", "いで", "いだ"),
        "す": ("さ", "し", "せ", "そ", "して", "した"),
        "つ": ("た", "ち", "て", "と", "って", "った"),
        "ぬ": ("な", "に", "ね", "の", "んで", "んだ"),
        "ぶ": ("ば", "び", "べ", "ぼ", "んで", "んだ"),
        "む": ("ま", "み", "め", "も", "んで", "んだ"),
        "る": ("ら", "り", "れ", "ろ", "って", "った"),
    ]

    private static func verb(_ lemma: String, as cls: WordClass) -> Verb? {
        switch cls {
        case .godan(let kind):
            guard let last = lemma.last, let row = godanRows[last] else { return nil }
            let stem = String(lemma.dropLast())
            let te = kind == .iku ? "って" : row.te
            let ta = kind == .iku ? "った" : row.ta
            return Verb(
                dictionary: lemma,
                masuStem: stem + (kind == .aru ? "い" : row.i),
                negativeStem: kind == .aruIrregular ? String(lemma.dropLast(2)) : stem + row.a,
                te: stem + te,
                ta: stem + ta,
                conditional: stem + row.e + "ば",
                volitional: stem + row.o + "う",
                imperative: stem + (kind == .aru ? "い" : row.e)
            )
        case .ichidan:
            return ichidanVerb(lemma, imperative: !lemma.hasSuffix("くれる"))
        case .kuru:
            let prefix = String(lemma.dropLast(2))
            let kanji = lemma.hasSuffix("来る")
            let ki = prefix + (kanji ? "来" : "き")
            let ko = prefix + (kanji ? "来" : "こ")
            let ku = prefix + (kanji ? "来" : "く")
            return Verb(
                dictionary: lemma, masuStem: ki, negativeStem: ko,
                te: ki + "て", ta: ki + "た",
                conditional: ku + "れば", volitional: ko + "よう", imperative: ko + "い"
            )
        case .suru, .suruNoun:
            let prefix = cls == .suru ? String(lemma.dropLast(2)) : lemma
            return Verb(
                dictionary: prefix + "する", masuStem: prefix + "し", negativeStem: prefix + "し",
                te: prefix + "して", ta: prefix + "した",
                conditional: prefix + "すれば", volitional: prefix + "しよう", imperative: prefix + "しろ"
            )
        case .iAdjective:
            return nil
        }
    }

    private static func ichidanVerb(_ lemma: String, imperative: Bool = true) -> Verb? {
        guard lemma.hasSuffix("る") else { return nil }
        let stem = String(lemma.dropLast())
        return Verb(
            dictionary: lemma, masuStem: stem, negativeStem: stem,
            te: stem + "て", ta: stem + "た",
            conditional: stem + "れば", volitional: stem + "よう",
            imperative: imperative ? stem + "ろ" : stem
        )
    }

    private static let potential = (name: "Potential", detail: "Can do.")
    private static let passive = (name: "Passive", detail: "Is done (to someone); also a respectful form.")
    private static let passiveOrPotential = (
        name: "Passive or potential",
        detail: "Is done (passive) or can do (potential); the sentence decides which."
    )
    private static let causative = (name: "Causative", detail: "Makes or lets someone do.")
    private static let causativePassive = (name: "Causative-passive", detail: "Is made to do.")

    /// Potential, passive, causative, and causative-passive verbs. Each conjugates as ichidan.
    private static func derivedVerbs(_ lemma: String, as cls: WordClass) -> [Derived] {
        func make(_ text: String, _ info: (name: String, detail: String)) -> Derived {
            Derived(dictionary: text, name: info.name, detail: info.detail)
        }
        switch cls {
        case .godan(let kind):
            guard kind != .aruIrregular, let last = lemma.last, let row = godanRows[last] else { return [] }
            let stem = String(lemma.dropLast())
            var out = [
                make(stem + row.e + "る", potential),
                make(stem + row.a + "れる", passive),
                make(stem + row.a + "せる", causative),
                make(stem + row.a + "せられる", causativePassive),
            ]
            if last != "す" {
                out.append(make(stem + row.a + "される", causativePassive))
            }
            return out
        case .ichidan:
            let stem = String(lemma.dropLast())
            return [
                make(stem + "られる", passiveOrPotential),
                make(stem + "れる", potential),
                make(stem + "させる", causative),
                make(stem + "させられる", causativePassive),
            ]
        case .kuru:
            let ko = String(lemma.dropLast(2)) + (lemma.hasSuffix("来る") ? "来" : "こ")
            return [
                make(ko + "られる", passiveOrPotential),
                make(ko + "れる", potential),
                make(ko + "させる", causative),
                make(ko + "させられる", causativePassive),
            ]
        case .suru, .suruNoun:
            let prefix = cls == .suru ? String(lemma.dropLast(2)) : lemma
            return [
                make(prefix + "できる", potential),
                make(prefix + "される", passive),
                make(prefix + "させる", causative),
                make(prefix + "させられる", causativePassive),
            ]
        case .iAdjective:
            return []
        }
    }

    private static func verbForms(_ v: Verb, extended: Bool) -> [Form] {
        func form(_ text: String, _ name: String, _ detail: String) -> Form {
            Form(text: text, match: Match(name: name, detail: detail))
        }
        var out: [Form] = [
            form(v.dictionary, "Dictionary form", "The plain, non-past form listed in dictionaries."),
            form(v.masuStem + "ます", "Polite", "Present or future, said politely (〜ます)."),
            form(v.masuStem + "ません", "Polite negative", "Negative, said politely (〜ません)."),
            form(v.masuStem + "ました", "Polite past", "Past tense, said politely (〜ました)."),
            form(v.masuStem + "ませんでした", "Polite negative past", "Negative past, said politely (〜ませんでした)."),
            form(v.ta, "Past", "Plain past tense (〜た)."),
            form(v.negativeStem + "ない", "Negative", "Plain negative: does not (〜ない)."),
            form(v.negativeStem + "なかった", "Negative past", "Plain negative past: did not (〜なかった)."),
            form(v.te, "Te-form", "Links to what comes next, or makes a request (〜て)."),
            form(v.negativeStem + "なくて", "Negative te-form", "Not doing, and so … (〜なくて)."),
            form(v.te + "いる", "Progressive", "Ongoing action, or the state that results (〜ている)."),
            form(v.te + "る", "Progressive", "Ongoing action or state, casual (〜てる)."),
            form(v.te + "いた", "Past progressive", "Was doing, or was in that state (〜ていた)."),
            form(v.ta + "ら", "Conditional", "If or when … (〜たら)."),
            form(v.conditional, "Conditional", "If … (〜ば)."),
        ]
        // てしまう "ends up doing" and its casual ちゃう; ちゃ is ては (〜ちゃだめ "must not").
        // 読んで → 読んじゃう: で contracts to じゃ.
        let cha = String(v.te.dropLast()) + (v.te.hasSuffix("で") ? "じゃ" : "ちゃ")
        let ending = String(cha.suffix(2))
        let endsUp = "Does it completely, or ends up doing it, often with regret"
        let endedUp = "Did it completely, or ended up doing it, often with regret"
        out += [
            form(v.te + "しまう", "Ends up doing", "\(endsUp) (〜てしまう)."),
            form(v.te + "しまった", "Ended up doing", "\(endedUp) (〜てしまった)."),
            form(v.te + "しまって", "Ends up doing, te-form", "\(endsUp), and … (〜てしまって)."),
            form(v.te + "しまい", "Ends up doing, linking", "\(endsUp); joins what follows in formal speech or writing (〜てしまい)."),
            form(v.te + "しまいます", "Ends up doing, polite", "\(endsUp), said politely (〜てしまいます)."),
            form(v.te + "しまいました", "Ended up doing, polite", "\(endedUp), said politely (〜てしまいました)."),
            form(cha + "う", "Ends up doing, casual", "\(endsUp). Casual 〜てしまう (〜\(ending)う)."),
            form(cha + "った", "Ended up doing, casual", "\(endedUp). Casual 〜てしまった (〜\(ending)った)."),
            form(cha + "って", "Ends up doing, casual te-form", "\(endsUp), and … Casual 〜てしまって (〜\(ending)って)."),
            form(cha + "ったら", "Ends up doing, conditional", "If or once it ends up done. Casual 〜てしまったら (〜\(ending)ったら)."),
            form(cha + "います", "Ends up doing, polite", "\(endsUp), said politely (〜\(ending)います)."),
            form(cha + "いました", "Ended up doing, polite", "\(endedUp), said politely (〜\(ending)いました)."),
            form(cha, "Casual ては", "If you do …; before だめ or いけない it means \"must not\" (〜\(ending) = 〜\(v.te.suffix(1))は)."),
            form(cha + "だめ", "Must not", "Must not do, casual (〜\(ending)だめ)."),
            form(cha + "ダメ", "Must not", "Must not do, casual (〜\(ending)ダメ)."),
            form(cha + "駄目", "Must not", "Must not do, casual (〜\(ending)駄目)."),
            form(cha + "いけない", "Must not", "Must not do (〜\(ending)いけない)."),
            form(cha + "いけません", "Must not, polite", "Must not do, said politely (〜\(ending)いけません)."),
        ]
        guard extended else { return out }
        out += [
            form(v.masuStem + "ましょう", "Polite volitional", "\"Let's …\" or \"Shall I …?\", said politely (〜ましょう)."),
            form(v.negativeStem + "ないで", "Negative te-form", "Without doing, or \"please don't\" (〜ないで)."),
            form(v.negativeStem + "なければ", "Negative conditional", "If not …; often part of \"must\" (〜なければ)."),
            form(v.te + "た", "Past progressive", "Was doing, casual (〜てた)."),
            form(v.te + "います", "Polite progressive", "Ongoing action or state, said politely (〜ています)."),
            form(v.te + "いました", "Polite past progressive", "Was doing, said politely (〜ていました)."),
            form(v.te + "いない", "Negative progressive", "Is not doing, or hasn't yet (〜ていない)."),
            form(v.te + "ない", "Negative progressive", "Is not doing, or hasn't yet, casual (〜てない)."),
            form(v.te + "いません", "Polite negative progressive", "Is not doing, or hasn't yet, said politely (〜ていません)."),
            form(v.te + "おります", "Humble progressive", "Ongoing action or state, said humbly about yourself (〜ております)."),
            form(v.te + "おりました", "Humble past progressive", "Was doing, said humbly about yourself (〜ておりました)."),
            form(v.te + "おりません", "Humble negative progressive", "Is not doing, or hasn't yet, said humbly (〜ておりません)."),
            form(v.te + "おり", "Formal progressive", "Ongoing action or state, linking to what follows in formal speech or writing (〜ており)."),
            form(v.masuStem + "たい", "Want to", "Want to do (〜たい)."),
            form(v.masuStem + "たくない", "Don't want to", "Don't want to do (〜たくない)."),
            form(v.masuStem + "たかった", "Wanted to", "Wanted to do (〜たかった)."),
            form(v.volitional, "Volitional", "\"Let's …\" or \"I'll …\", plain (〜う／〜よう)."),
        ]
        // Before the masu stem: いらっしゃい / くれ read as commands, not bare stems.
        if let imperative = v.imperative {
            out.append(form(imperative, "Imperative", "A blunt command."))
        }
        out.append(form(v.masuStem, "Masu stem", "The stem that joins other words, as in 〜ます or 〜ながら."))
        return out
    }

    private static func adjectiveForms(_ lemma: String) -> [Form] {
        // いい conjugates from よ (よかった); 良い / よい already have that stem.
        let stem = lemma.hasSuffix("いい") ? String(lemma.dropLast(2)) + "よ" : String(lemma.dropLast())
        func form(_ text: String, _ name: String, _ detail: String) -> Form {
            Form(text: text, match: Match(name: name, detail: detail))
        }
        return [
            form(lemma, "Dictionary form", "The plain, non-past form listed in dictionaries."),
            form(lemma + "です", "Polite", "Said politely (〜です)."),
            form(stem + "かった", "Past", "Was … (〜かった)."),
            form(stem + "かったです", "Polite past", "Was …, said politely (〜かったです)."),
            form(stem + "くない", "Negative", "Is not … (〜くない)."),
            form(stem + "くないです", "Polite negative", "Is not …, said politely (〜くないです)."),
            form(stem + "くありません", "Polite negative", "Is not …, said politely (〜くありません)."),
            form(stem + "くなかった", "Negative past", "Was not … (〜くなかった)."),
            form(stem + "くなかったです", "Polite negative past", "Was not …, said politely (〜くなかったです)."),
            form(stem + "くて", "Te-form", "Links to what comes next: … and … (〜くて)."),
            form(stem + "く", "Adverb form", "Describes how something is done, or joins なる / する (〜く)."),
            form(stem + "ければ", "Conditional", "If … (〜ければ)."),
            form(stem + "かったら", "Conditional", "If or when … (〜かったら)."),
            // いい → よさそう; other adjectives drop い (高そう).
            form(stem + (lemma.hasSuffix("いい") ? "さそう" : "そう"), "Looks like", "Looks … (〜そう)."),
        ]
    }
}
