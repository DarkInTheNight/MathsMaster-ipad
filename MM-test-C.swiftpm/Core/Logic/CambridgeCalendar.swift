import Foundation

/// Cambridge term and week numbering. Week 1 starts on the first Thursday of Full Term
/// (Full Term starts on a Tuesday, so its first Tuesday and Wednesday are "week 0").
enum CambridgeCalendar {
    struct Position: Hashable, Sendable {
        var term: TermName
        var week: Int
        /// False in the vacation after the term (week counting continues from the last term).
        var inFullTerm: Bool

        var label: String {
            inFullTerm ? "\(term.displayName), week \(week)" : "After \(term.displayName) term"
        }
    }

    static func weekOne(of term: Term, calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarDate {
        // weekday: 1 = Sunday … 5 = Thursday
        let start = term.start.date(in: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (5 - weekday + 7) % 7
        return term.start.adding(days: offset, calendar: calendar)
    }

    static func week(of day: CalendarDate, in term: Term, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let days = weekOne(of: term, calendar: calendar).days(to: day, calendar: calendar)
        // floor division, so the Tuesday/Wednesday before week 1 are week 0
        let weeks = days >= 0 ? days / 7 : -((-days + 6) / 7)
        return weeks + 1
    }

    /// The term `day` falls in (or the most recent term before it), with its week number.
    static func position(of day: CalendarDate, in year: AcademicYear, calendar: Calendar = Calendar(identifier: .gregorian)) -> Position? {
        let terms = year.terms.sorted { $0.start < $1.start }
        if let current = terms.first(where: { $0.start <= day && day <= $0.end }) {
            return Position(term: current.name, week: week(of: day, in: current, calendar: calendar), inFullTerm: true)
        }
        if let previous = terms.last(where: { $0.end < day }) {
            return Position(term: previous.name, week: week(of: day, in: previous, calendar: calendar), inFullTerm: false)
        }
        if let first = terms.first {
            return Position(term: first.name, week: week(of: day, in: first, calendar: calendar), inFullTerm: false)
        }
        return nil
    }

    /// The term whose courses get new cards and sit at the top of the sidebar.
    static func currentTerm(on day: CalendarDate, in year: AcademicYear) -> TermName {
        let terms = year.terms.sorted { $0.start < $1.start }
        if let t = terms.first(where: { day <= $0.end }) { return t.name }
        return terms.last?.name ?? .michaelmas
    }
}
