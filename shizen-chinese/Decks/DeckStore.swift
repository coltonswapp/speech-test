//
//  DeckStore.swift
//  shizen-chinese
//
//  Local JSON decks (not CEDICT). Default Inbox plus user-created stacks.
//

import Foundation

struct DeckCard: Codable, Equatable, Identifiable {
    var id: String
    var simplified: String
    var pinyinMarked: String
    var glossary: String
    var isDue: Bool

    init(
        id: String = UUID().uuidString,
        simplified: String,
        pinyinMarked: String,
        glossary: String,
        isDue: Bool = true
    ) {
        self.id = id
        self.simplified = simplified
        self.pinyinMarked = pinyinMarked
        self.glossary = glossary
        self.isDue = isDue
    }

    init(entry: CedictEntry) {
        self.init(
            simplified: entry.simplified,
            pinyinMarked: entry.pinyinMarked,
            glossary: entry.glossary
        )
    }
}

struct WordDeck: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var cards: [DeckCard]

    var dueCount: Int { cards.filter(\.isDue).count }

    var sampleHanzi: String {
        cards.first?.simplified ?? "字"
    }

    var subtitle: String {
        if cards.isEmpty {
            return "Empty · save words from the dictionary"
        }
        let due = dueCount
        if due == 0 {
            return "\(cards.count) words · all caught up"
        }
        return "\(due) due · \(cards.count) words"
    }
}

final class DeckStore {
    static let shared = DeckStore()
    static let inboxID = "inbox"
    static let didChangeNotification = Notification.Name("ChineseDeckStoreDidChange")

    private static let defaultsKey = "com.Swappfunc.shizen-chinese.decks"

    private(set) var decks: [WordDeck] = []

    var inbox: WordDeck {
        decks.first { $0.id == Self.inboxID } ?? WordDeck(id: Self.inboxID, name: "Inbox", cards: [])
    }

    private init() {
        load()
        ensureInbox()
    }

    func deck(id: String) -> WordDeck? {
        decks.first { $0.id == id }
    }

    @discardableResult
    func add(entry: CedictEntry, toDeckID deckID: String) -> Bool {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return false }
        if decks[index].cards.contains(where: { $0.simplified == entry.simplified }) {
            return false
        }
        decks[index].cards.append(DeckCard(entry: entry))
        persist()
        return true
    }

    @discardableResult
    func createDeck(name: String) -> WordDeck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = WordDeck(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "New deck" : trimmed,
            cards: []
        )
        decks.append(deck)
        persist()
        return deck
    }

    func markReviewed(deckID: String, cardID: String, known: Bool) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == cardID })
        else { return }
        decks[deckIndex].cards[cardIndex].isDue = !known
        persist()
    }

    func reviewCards(in deckID: String) -> [DeckCard] {
        guard let deck = deck(id: deckID) else { return [] }
        let due = deck.cards.filter(\.isDue)
        return due.isEmpty ? deck.cards : due
    }

    private func ensureInbox() {
        guard !decks.contains(where: { $0.id == Self.inboxID }) else { return }
        decks.insert(WordDeck(id: Self.inboxID, name: "Inbox", cards: []), at: 0)
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            decks = []
            return
        }
        do {
            decks = try JSONDecoder().decode([WordDeck].self, from: data)
        } catch {
            print("DeckStore: failed to decode decks: \(error)")
            decks = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(decks)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            print("DeckStore: failed to save decks: \(error)")
        }
    }
}
