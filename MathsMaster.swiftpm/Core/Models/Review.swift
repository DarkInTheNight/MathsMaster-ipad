import Foundation

/// The four grades. In the log, `rating: 0` means "not a review" (see `ReviewEntry.rating`).
enum Rating: Int, Codable, CaseIterable, Hashable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// What a log line records. Matches the VPS's Anki import (`server/API.md`) plus the app's own `undo`.
enum ReviewKind: String, Codable, Hashable, Sendable {
    case learn, review, relearn, filtered
    /// Anki "Forget" (`intervalDays` 0) or "Set due date"; `rating` is 0.
    case manual, reschedule
    /// Cancels the line whose id is `undoes` (the log is append-only, so undo is a new line).
    case undo
    /// A cram review that must not change the schedule.
    case cram
}

/// Anki's own numbers for an imported review (only what the app reads).
struct AnkiRevlogInfo: Codable, Hashable, Sendable {
    var revlogId: Int64?
    var intervalDays: Int?
    var intervalSeconds: Int?
}

/// One line of an append-only review log:
/// `Reviews/<installID>/<yyyy-MM>.jsonl` (design plan §7.3–7.5).
/// Each app install writes only its own file, so logs never conflict between the Playgrounds
/// and SideStore copies; the VPS import writes `Reviews/anki-import/…`.
/// Card scheduling state is derived by replaying all logs in time order (`FSRS.replay`).
struct ReviewEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var card: UUID
    var t: Date
    /// nil = `0` on disk: not a review (manual reschedule, forget, undo).
    var rating: Rating?
    /// Time spent on the card, in milliseconds.
    var ms: Int
    var session: UUID?
    var kind: ReviewKind?
    var source: String?
    var undoes: UUID?
    var anki: AnkiRevlogInfo?

    init(id: UUID = UUID(), card: UUID, t: Date, rating: Rating?, ms: Int, session: UUID? = nil,
         kind: ReviewKind? = nil, source: String? = nil, undoes: UUID? = nil, anki: AnkiRevlogInfo? = nil) {
        self.id = id
        self.card = card
        self.t = t
        self.rating = rating
        self.ms = ms
        self.session = session
        self.kind = kind
        self.source = source
        self.undoes = undoes
        self.anki = anki
    }

    static func undo(of entry: ReviewEntry, at date: Date = Date()) -> ReviewEntry {
        ReviewEntry(card: entry.card, t: date, rating: nil, ms: 0, session: entry.session, kind: .undo, undoes: entry.id)
    }

    enum CodingKeys: String, CodingKey {
        case id, card, t, rating, ms, session, kind, source, undoes, anki
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        card = try c.decode(UUID.self, forKey: .card)
        t = try c.decode(Date.self, forKey: .t)
        let raw = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        rating = Rating(rawValue: raw)
        ms = try c.decodeIfPresent(Int.self, forKey: .ms) ?? 0
        session = try? c.decodeIfPresent(UUID.self, forKey: .session)
        kind = try? c.decodeIfPresent(ReviewKind.self, forKey: .kind)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        undoes = try? c.decodeIfPresent(UUID.self, forKey: .undoes)
        anki = try? c.decodeIfPresent(AnkiRevlogInfo.self, forKey: .anki)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(card, forKey: .card)
        try c.encode(t, forKey: .t)
        try c.encode(rating?.rawValue ?? 0, forKey: .rating)
        try c.encode(ms, forKey: .ms)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(undoes, forKey: .undoes)
        try c.encodeIfPresent(anki, forKey: .anki)
    }
}
