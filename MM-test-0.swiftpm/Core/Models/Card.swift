import Foundation

/// One flashcard (design plan §4.1). Fields are Anki-compatible HTML + MathJax:
/// `front` is plain text with `\( … \)` / `\[ … \]`; `back` is the guidelines' HTML subset
/// (`<b> <i> <br> <ul> <li>` + inline `<svg>`).
struct Card: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var courseID: UUID
    var front: String
    var back: String
    var label: CardLabel
    var lecture: Int?
    var tags: [String] = []
    var source: Anchor?
    /// Relative path inside the course's `cards-media/` folder.
    var image: String?
    var frontInk: String?
    var backInk: String?
    var flagged: Bool = false
    var suspended: Bool = false
    var origin: CardOrigin
    var revisions: [CardRevision] = []
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    static func new(courseID: UUID, front: String, back: String, origin: CardOrigin = CardOrigin(kind: .you), now: Date = Date()) -> Card {
        Card(id: UUID(), courseID: courseID, front: front, back: back, label: CardLabel.infer(fromFront: front),
             origin: origin, createdAt: now, updatedAt: now)
    }
}

enum CardLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case definition, theorem, practice, synthesis, other

    var displayName: String { rawValue.capitalized }

    /// Derive the label from the guidelines' front patterns.
    static func infer(fromFront front: String) -> CardLabel {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if f.hasPrefix("practice") { return .practice }
        if f.hasPrefix("synthesis") { return .synthesis }
        if f.hasPrefix("definition") { return .definition }
        if f.hasPrefix("statement and proof") || f.hasPrefix("statement of") || f.contains("theorem") || f.contains("lemma") { return .theorem }
        return .other
    }
}

struct CardOrigin: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case you, claude, anki }
    var kind: Kind
    var jobID: String?
    var threadID: String?
    var ankiNoteID: Int64?
    var ankiGUID: String?
}

/// An earlier version of a card. Every edit appends one, so AI edits are reversible.
struct CardRevision: Codable, Hashable, Sendable {
    var at: Date
    var by: CardOrigin.Kind
    var front: String
    var back: String
    var note: String?
}

/// `cards.json` in each course folder: the course deck.
struct DeckFile: Codable, Hashable, Sendable {
    static let currentSchema = 1
    var schemaVersion: Int = DeckFile.currentSchema
    var courseID: UUID
    var cards: [Card]
}
