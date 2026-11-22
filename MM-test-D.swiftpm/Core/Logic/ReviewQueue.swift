import Foundation

/// Study days start at 4 am local time (like Anki), so a late-night session counts for the day before.
enum StudyDay {
    static let rolloverHour = 4

    /// The start of the study day containing `date`.
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let midnight = calendar.startOfDay(for: shifted)
        return midnight.addingTimeInterval(Double(rolloverHour) * 3600)
    }

    static func end(of date: Date, calendar: Calendar = .current) -> Date {
        let start = start(of: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// The calendar day a moment belongs to, as a study day.
    static func day(of date: Date, calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(date.addingTimeInterval(-Double(rolloverHour) * 3600), calendar: calendar)
    }
}

/// Which cards are due and in what order (design plan §4.2).
struct ReviewQueue {
    /// Learning cards due within this window are shown now (Anki's learn-ahead limit).
    static let learnAhead: TimeInterval = 20 * 60

    struct Counts: Hashable, Sendable {
        var new = 0
        var learning = 0
        var review = 0
        var total: Int { new + learning + review }
    }

    let fsrs: FSRS
    let now: Date
    var calendar: Calendar = .current

    func isDueLearning(_ s: CardSchedule) -> Bool {
        s.isLearning && (s.due ?? now) <= now.addingTimeInterval(ReviewQueue.learnAhead)
    }

    func isDueReview(_ s: CardSchedule) -> Bool {
        s.phase == .review && (s.due ?? now) < StudyDay.end(of: now, calendar: calendar)
    }

    static func isStudyable(_ card: Card) -> Bool { !card.isDeleted && !card.suspended }

    /// Cards introduced (first reviewed) today, across all decks.
    func newIntroducedToday(_ states: [UUID: CardSchedule]) -> Int {
        let start = StudyDay.start(of: now, calendar: calendar)
        return states.values.filter { ($0.firstReview ?? .distantPast) >= start }.count
    }

    /// Builds the session order: due learning cards first, then reviews by lowest retrievability
    /// round-robin across courses, with new cards spread evenly through.
    /// - Parameters:
    ///   - newLimit: how many new cards may still be introduced today.
    ///   - allowsNew: whether a card's course may introduce new cards (current-term courses only, §4.2).
    func build(cards: [Card], states: [UUID: CardSchedule], newLimit: Int, allowsNew: (Card) -> Bool) -> [Card] {
        let live = cards.filter(ReviewQueue.isStudyable)
        let learning = live
            .filter { isDueLearning(states[$0.id] ?? .new) }
            .sorted { (states[$0.id]?.due ?? now) < (states[$1.id]?.due ?? now) }

        let reviews = ReviewQueue.roundRobin(
            live.filter { isDueReview(states[$0.id] ?? .new) },
            sortedBy: { fsrs.exactRetrievability(of: states[$0.id] ?? .new, at: now) }
        )

        let newCards = Array(ReviewQueue.roundRobin(
            live.filter { (states[$0.id] ?? .new).isNew && allowsNew($0) },
            sortedBy: { $0.createdAt.timeIntervalSince1970 }
        ).prefix(max(newLimit, 0)))

        return learning + ReviewQueue.spread(newCards, into: reviews)
    }

    func counts(cards: [Card], states: [UUID: CardSchedule], newLimit: Int, allowsNew: (Card) -> Bool) -> Counts {
        var c = Counts()
        var newAvailable = 0
        for card in cards where ReviewQueue.isStudyable(card) {
            let s = states[card.id] ?? .new
            if isDueLearning(s) { c.learning += 1 }
            else if isDueReview(s) { c.review += 1 }
            else if s.isNew && allowsNew(card) { newAvailable += 1 }
        }
        c.new = min(newAvailable, max(newLimit, 0))
        return c
    }

    /// The next time anything becomes due (for "All done · next due …").
    func nextDue(cards: [Card], states: [UUID: CardSchedule]) -> Date? {
        cards.filter(ReviewQueue.isStudyable).compactMap { card -> Date? in
            guard let s = states[card.id], !s.isNew, let due = s.due, due > now else { return nil }
            return due
        }.min()
    }

    /// Groups by course (each sorted ascending by `key`) and interleaves the groups.
    static func roundRobin(_ cards: [Card], sortedBy key: (Card) -> Double) -> [Card] {
        var groups: [UUID: [Card]] = [:]
        for card in cards { groups[card.courseID, default: []].append(card) }
        var queues = groups
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key.uuidString < $1.key.uuidString }
            .map { group in group.value.sorted { (key($0), $0.id.uuidString) < (key($1), $1.id.uuidString) } }
        var result: [Card] = []
        result.reserveCapacity(cards.count)
        var index = 0
        while !queues.isEmpty {
            let i = index % queues.count
            result.append(queues[i].removeFirst())
            if queues[i].isEmpty {
                queues.remove(at: i)
            } else {
                index += 1
            }
        }
        return result
    }

    /// Inserts `extra` evenly through `base`.
    static func spread<T>(_ extra: [T], into base: [T]) -> [T] {
        guard !extra.isEmpty else { return base }
        guard !base.isEmpty else { return extra }
        var result: [T] = []
        let gap = Double(base.count + extra.count) / Double(extra.count)
        var nextSlot = gap / 2
        var e = 0, b = 0
        for position in 0..<(base.count + extra.count) {
            if e < extra.count && (Double(position) >= nextSlot.rounded(.down) || b >= base.count) {
                result.append(extra[e]); e += 1; nextSlot += gap
            } else {
                result.append(base[b]); b += 1
            }
        }
        return result
    }
}
