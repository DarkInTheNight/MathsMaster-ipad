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

extension Card {
    enum CodingKeys: String, CodingKey {
        case id, courseID, front, back, label, lecture, tags, source, image, frontInk, backInk
        case flagged, suspended, origin, revisions, createdAt, updatedAt, deletedAt
    }

    /// Tolerant decoding: only `id` is required, so cards written by other tools (or older builds) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        courseID = (try? c.decodeIfPresent(UUID.self, forKey: .courseID)) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        front = (try? c.decodeIfPresent(String.self, forKey: .front)) ?? ""
        back = (try? c.decodeIfPresent(String.self, forKey: .back)) ?? ""
        label = (try? c.decodeIfPresent(CardLabel.self, forKey: .label)) ?? CardLabel.infer(fromFront: front)
        lecture = try? c.decodeIfPresent(Int.self, forKey: .lecture)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        source = try? c.decodeIfPresent(Anchor.self, forKey: .source)
        image = try? c.decodeIfPresent(String.self, forKey: .image)
        frontInk = try? c.decodeIfPresent(String.self, forKey: .frontInk)
        backInk = try? c.decodeIfPresent(String.self, forKey: .backInk)
        flagged = (try? c.decodeIfPresent(Bool.self, forKey: .flagged)) ?? false
        suspended = (try? c.decodeIfPresent(Bool.self, forKey: .suspended)) ?? false
        origin = (try? c.decodeIfPresent(CardOrigin.self, forKey: .origin)) ?? CardOrigin(kind: .you)
        revisions = (try? c.decodeIfPresent([CardRevision].self, forKey: .revisions)) ?? []
        let created = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        createdAt = created
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? created
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// Applies an edit, keeping the previous text as a revision (design plan §4.5: edits are reversible).
    mutating func edit(front newFront: String, back newBack: String, by: CardOrigin.Kind = .you, note: String? = nil, now: Date = Date()) {
        guard newFront != front || newBack != back else { return }
        revisions.append(CardRevision(at: updatedAt, by: by, front: front, back: back, note: note))
        front = newFront
        back = newBack
        updatedAt = now
    }
}

enum CardLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case definition, theorem, practice, synthesis, other

    /// Accepts any case ("Theorem" from Claude jobs, "theorem" on disk); unknown values become `.other`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardLabel(rawValue: raw.lowercased()) ?? .other
    }

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
    /// Per-deck scheduler overrides, e.g. the FSRS parameters from an imported Anki preset (design plan §4.6).
    var scheduler: DeckScheduler?
}

/// Matches the `scheduler` object of the VPS's Anki import result (server/API.md).
struct DeckScheduler: Codable, Hashable, Sendable {
    var fsrsParams: [Double]?
    var fsrsVersion: Int?
    var desiredRetention: Double?
}
