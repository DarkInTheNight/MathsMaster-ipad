import Foundation

/// Merging decks card by card (design plan §7.5): the newest `updatedAt` wins per card,
/// deletions are tombstones (`deletedAt`), purged after 60 days.
enum DeckMerge {
    static let tombstoneLifetime: TimeInterval = 60 * 86_400

    static func merge(_ a: [Card], _ b: [Card]) -> [Card] {
        var byID: [UUID: Card] = [:]
        var order: [UUID] = []
        for card in a + b {
            if let existing = byID[card.id] {
                if newer(card, than: existing) { byID[card.id] = card }
            } else {
                byID[card.id] = card
                order.append(card.id)
            }
        }
        return order.compactMap { byID[$0] }
    }

    static func merge(_ a: DeckFile, _ b: DeckFile) -> DeckFile {
        var result = a
        result.cards = merge(a.cards, b.cards)
        result.scheduler = a.scheduler ?? b.scheduler
        result.schemaVersion = max(a.schemaVersion, b.schemaVersion)
        return result
    }

    /// A card version is newer if edited later; on a tie, a deletion wins (so deletes stick).
    static func newer(_ x: Card, than y: Card) -> Bool {
        let xt = max(x.updatedAt, x.deletedAt ?? .distantPast)
        let yt = max(y.updatedAt, y.deletedAt ?? .distantPast)
        if xt != yt { return xt > yt }
        return x.isDeleted && !y.isDeleted
    }

    /// Drops tombstones older than 60 days.
    static func purgeTombstones(_ cards: [Card], now: Date = Date()) -> [Card] {
        cards.filter { card in
            guard let deleted = card.deletedAt else { return true }
            return now.timeIntervalSince(deleted) < tombstoneLifetime
        }
    }

    /// iCloud conflict copies of `cards.json` look like `cards 2.json`.
    static func isConflictCopy(fileName: String) -> Bool {
        guard fileName.hasPrefix("cards "), fileName.hasSuffix(".json") else { return false }
        let middle = fileName.dropFirst("cards ".count).dropLast(".json".count)
        return !middle.isEmpty && middle.allSatisfy(\.isNumber)
    }
}
