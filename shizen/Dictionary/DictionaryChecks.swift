//
//  DictionaryChecks.swift
//  shizen
//
//  What a token tap's callout shows for a surface (defined / depends on context / missing),
//  the must-define fixture list, and the words flagged by press-and-hold on a callout.
//  The Dictionary checks screen (Settings → Tokenization) shows all three.
//

import Foundation
import InteractionKit

// MARK: - Callout outcome

/// What the rich callout shows for one surface, read from the same lookup it uses.
struct DictionaryCalloutOutcome: Hashable {
    enum Status: String, Codable {
        /// Senses from one dictionary entry.
        case defined
        /// "Depends on context" with candidate words listed.
        case ambiguous
        /// No entry, or no candidates to list.
        case missing
    }

    let status: Status
    /// The entry's headword when `defined` (ここ → 此処).
    let headword: String?
    /// Senses when `defined`; candidate lines when `ambiguous`.
    let lines: [String]
    /// The sheet's lookup note, e.g. "Usually written in kana · kanji 此処".
    var note: String? = nil

    /// One line for lists and exports: "此処 · here; this place".
    var summary: String {
        switch status {
        case .defined:
            let gloss = lines.first ?? ""
            if let headword { return gloss.isEmpty ? headword : "\(headword) · \(gloss)" }
            return gloss
        case .ambiguous:
            return "Depends on context: " + lines.joined(separator: " / ")
        case .missing:
            return "No definition"
        }
    }

    static func evaluate(surface: String, sentence: String?) -> DictionaryCalloutOutcome {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = JMDictStore.shared
        let lookup = store.lookup(forSurface: trimmed, inSentence: sentence)
        guard let primary = lookup.primaryEntry else {
            return DictionaryCalloutOutcome(status: .missing, headword: nil, lines: [])
        }
        let content = DefinitionCalloutContent.jmdict(surface: trimmed, sentence: sentence)
        let contextSensitive = store.isContextSensitiveKanaLookup(lookup, inSentence: sentence)
        let note = KanaLookupNote.make(surface: trimmed, lookup: lookup, contextSensitive: contextSensitive)?
            .text(listsCandidates: false)
        if contextSensitive {
            return DictionaryCalloutOutcome(
                status: content.senses.isEmpty ? .missing : .ambiguous,
                headword: nil,
                lines: content.senses,
                note: note
            )
        }
        return DictionaryCalloutOutcome(
            status: content.senses.isEmpty ? .missing : .defined,
            headword: primary.expression,
            lines: content.senses,
            note: note
        )
    }
}

// MARK: - Must-define fixtures

/// Words a token tap must define. `expectedHeadword` nil means any definition passes.
struct DictionaryCheckFixture: Hashable {
    let surface: String
    let expectedHeadword: String?
    let sentence: String?
    let note: String

    init(_ surface: String, _ expectedHeadword: String?, sentence: String? = nil, note: String = "") {
        self.surface = surface
        self.expectedHeadword = expectedHeadword
        self.sentence = sentence
        self.note = note
    }

    func passes(_ outcome: DictionaryCalloutOutcome) -> Bool {
        guard outcome.status == .defined else { return false }
        guard let expectedHeadword else { return true }
        return outcome.headword == expectedHeadword
    }

    struct Section: Hashable {
        let title: String
        let fixtures: [DictionaryCheckFixture]
    }

    static let catalog: [Section] = [
        Section(title: "Places & question words", fixtures: [
            DictionaryCheckFixture("ここ", "此処", sentence: "ここすごいんですよ", note: "not 個々"),
            DictionaryCheckFixture("そこ", "其処", note: "not 底"),
            DictionaryCheckFixture("あそこ", "彼処"),
            DictionaryCheckFixture("どこ", "何処"),
            DictionaryCheckFixture("なに", "何"),
            DictionaryCheckFixture("いつ", "何時"),
            DictionaryCheckFixture("これ", "此れ"),
            DictionaryCheckFixture("それ", "其れ"),
            DictionaryCheckFixture("この", "此の"),
            DictionaryCheckFixture("その", "其の", note: "not 園"),
            DictionaryCheckFixture("どう", "如何", note: "not 銅"),
        ]),
        Section(title: "Everyday words in kana", fixtures: [
            DictionaryCheckFixture("すごい", "凄い", sentence: "ここすごいんですよ"),
            DictionaryCheckFixture("ちょっと", "一寸"),
            DictionaryCheckFixture("やはり", "矢張り"),
            DictionaryCheckFixture("やっぱり", "矢っ張り"),
            DictionaryCheckFixture("とても", "迚も"),
            DictionaryCheckFixture("たくさん", "沢山"),
            DictionaryCheckFixture("まだ", "未だ"),
            DictionaryCheckFixture("よろしく", "宜しく"),
            DictionaryCheckFixture("ありがとう", "有難う"),
            DictionaryCheckFixture("おいしい", "美味しい"),
            DictionaryCheckFixture("きれい", "綺麗"),
            DictionaryCheckFixture("だめ", "駄目"),
            DictionaryCheckFixture("みんな", nil, note: "皆"),
        ]),
        Section(title: "Nouns behind grammar", fixtures: [
            DictionaryCheckFixture("こと", "事", note: "not 琴"),
            DictionaryCheckFixture("もの", nil, note: "物 or もの"),
            DictionaryCheckFixture("ところ", "所"),
            DictionaryCheckFixture("ため", "為"),
            DictionaryCheckFixture("はず", "筈"),
            DictionaryCheckFixture("まで", "迄"),
            DictionaryCheckFixture("だけ", "丈"),
        ]),
        Section(title: "Verbs in kana", fixtures: [
            DictionaryCheckFixture("わかる", "分かる"),
            DictionaryCheckFixture("できる", "出来る"),
            DictionaryCheckFixture("する", "為る"),
            DictionaryCheckFixture("いる", "居る", note: "pinned · not 要る"),
            DictionaryCheckFixture("ある", "有る", note: "pinned"),
            DictionaryCheckFixture("なる", "成る", note: "pinned · not 生る"),
            DictionaryCheckFixture("いく", "行く"),
            DictionaryCheckFixture("くる", "来る"),
        ]),
    ]
}

// MARK: - Flagged words

/// A word flagged from a callout (press and hold) because its definition was missing or wrong.
struct DictionaryFlag: Codable, Hashable, Identifiable {
    let id: UUID
    let surface: String
    let sentence: String?
    /// Clip or lesson title, when known.
    let source: String?
    /// What the callout showed when flagged (`DictionaryCalloutOutcome.summary`).
    let shownAs: String
    let flaggedAt: Date
}

/// Flagged words, kept in Application Support as JSON. Main thread only.
final class DictionaryFlagStore {
    static let shared = DictionaryFlagStore()
    static let didChange = Notification.Name("DictionaryFlagStore.didChange")

    private(set) var flags: [DictionaryFlag] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("dictionary-flags.json")
    }()

    private init() {
        load()
    }

    /// Adds a flag, or moves an existing one for the same word and sentence to the top.
    @discardableResult
    func flag(surface: String, sentence: String?, source: String?) -> DictionaryFlag {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
        flags.removeAll { $0.surface == trimmed && $0.sentence == trimmedSentence }
        let flag = DictionaryFlag(
            id: UUID(),
            surface: trimmed,
            sentence: trimmedSentence,
            source: source,
            shownAs: DictionaryCalloutOutcome.evaluate(surface: trimmed, sentence: trimmedSentence).summary,
            flaggedAt: Date()
        )
        flags.insert(flag, at: 0)
        save()
        return flag
    }

    func remove(id: UUID) {
        flags.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        flags = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        flags = (try? decoder.decode([DictionaryFlag].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(flags).write(to: fileURL, options: .atomic)
        } catch {
            print("DictionaryFlagStore: save failed: \(error)")
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
