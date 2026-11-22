import Foundation

enum Rating: Int, Codable, CaseIterable, Hashable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4
}

/// One line of an append-only review log:
/// `Reviews/<installID>/<yyyy-MM>.jsonl` (design plan §7.3–7.5).
/// Card scheduling state is derived by replaying all logs in time order.
struct ReviewEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var card: UUID
    var t: Date
    var rating: Rating
    /// Time spent on the card, in milliseconds.
    var ms: Int
    var session: UUID?
}
