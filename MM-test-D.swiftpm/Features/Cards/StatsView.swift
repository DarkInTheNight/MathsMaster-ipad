import SwiftUI
import Charts

/// Pure statistics over the review log (unit-tested in Core).
enum Stats {
    /// Consecutive study days with at least one review, ending today (or yesterday).
    static func streak(reviews: [ReviewEntry], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(reviews.map { StudyDay.day(of: $0.t, calendar: calendar) })
        var day = StudyDay.day(of: now, calendar: calendar)
        if !days.contains(day) { day = day.adding(days: -1, calendar: calendar) }
        var n = 0
        while days.contains(day) { n += 1; day = day.adding(days: -1, calendar: calendar) }
        return n
    }

    /// Fraction of review-phase answers that weren't Again.
    static func retention(reviews: [ReviewEntry], since: Date, matureOnly: Bool = false, phaseBefore: (ReviewEntry) -> CardPhase?) -> Double? {
        let r = reviews.filter { $0.t >= since && phaseBefore($0) == .review }
        guard !r.isEmpty else { return nil }
        return Double(r.filter { $0.rating != .again }.count) / Double(r.count)
    }
}

struct StatsView: View {
    @Environment(CardStore.self) private var store
    @Environment(LibraryStore.self) private var library

    private struct DayCount: Identifiable { let id: Date; let count: Int }

    var body: some View {
        let now = Date()
        let reviews = store.effectiveReviews
        let dayStart = StudyDay.start(of: now)
        let past = (0..<30).reversed().map { dayStart.addingTimeInterval(Double(-$0) * 86_400) }
        let perDay = past.map { d in DayCount(id: d, count: reviews.filter { $0.t >= d && $0.t < d.addingTimeInterval(86_400) }.count) }
        let forecast = (0..<30).map { n -> DayCount in
            let d = dayStart.addingTimeInterval(Double(n) * 86_400)
            let c = store.cards.filter { card in
                guard !card.isDeleted, !card.suspended, let s = store.states[card.id], s.phase == .review, let due = s.due else { return false }
                return n == 0 ? due < d.addingTimeInterval(86_400) : (due >= d && due < d.addingTimeInterval(86_400))
            }.count
            return DayCount(id: d, count: c)
        }
        var maturity = [("New", 0), ("Learning", 0), ("Young", 0), ("Mature", 0)]
        for card in store.cards where !card.isDeleted {
            let s = store.state(of: card)
            if s.isNew { maturity[0].1 += 1 } else if s.isLearning { maturity[1].1 += 1 } else if s.isMature { maturity[3].1 += 1 } else { maturity[2].1 += 1 }
        }
        let total30 = perDay.map(\.count).reduce(0, +)
        let minutes = Double(reviews.filter { $0.t >= dayStart.addingTimeInterval(-29 * 86_400) }.map(\.ms).reduce(0, +)) / 60_000

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    stat("Streak", "\(Stats.streak(reviews: reviews)) days")
                    stat("Reviews (30 d)", "\(total30)")
                    stat("Time (30 d)", String(format: "%.0f min", minutes))
                    stat("Cards", "\(store.cards.filter { !$0.isDeleted }.count)")
                    stat("Retention (30 d)", retentionText(reviews, since: dayStart.addingTimeInterval(-29 * 86_400)))
                }
                chart("Reviews per day", perDay, Theme.accent)
                chart("Due forecast (next 30 days)", forecast, Theme.easy)
                Panel {
                    VStack(alignment: .leading) {
                        Text("Maturity").font(.headline)
                        Chart(maturity, id: \.0) { BarMark(x: .value("State", $0.0), y: .value("Cards", $0.1)).foregroundStyle(Theme.good) }
                            .frame(height: 180)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Statistics")
    }

    /// Retention is computed by replaying, so the phase before each review is known exactly.
    private func retentionText(_ reviews: [ReviewEntry], since: Date) -> String {
        var before: [UUID: CardPhase] = [:]
        _ = store.fsrs.replay(store.entries) { entry, prior, _ in before[entry.id] = prior.phase }
        guard let r = Stats.retention(reviews: reviews, since: since, phaseBefore: { before[$0.id] }) else { return "–" }
        return "\(Int((r * 100).rounded()))%"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(Theme.ink2)
                Text(value).font(.title2.bold().monospacedDigit())
            }
        }
    }

    private func chart(_ title: String, _ data: [DayCount], _ colour: Color) -> some View {
        Panel {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Chart(data) { BarMark(x: .value("Day", $0.id, unit: .day), y: .value("Cards", $0.count)).foregroundStyle(colour) }
                    .frame(height: 180)
            }
        }
    }
}
