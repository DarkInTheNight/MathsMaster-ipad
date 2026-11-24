import Foundation
import Observation

/// Decks, review logs and derived scheduling state (workstream C).
/// Files are the truth: `Courses/<course>/cards.json` and every `Reviews/**/*.jsonl`.
/// This install appends only to its own `Reviews/<installID>/<yyyy-MM>.jsonl`.
@MainActor
@Observable
final class CardStore {
    private(set) var cards: [Card] = []
    private(set) var states: [UUID: CardSchedule] = [:]
    private(set) var entries: [ReviewEntry] = []
    private(set) var loaded = false
    private(set) var newPerDay = 15
    private(set) var desiredRetention = 0.9
    @ObservationIgnored private var schedulers: [UUID: DeckScheduler] = [:]
    @ObservationIgnored private var deckFiles: [UUID: DeckFile] = [:]
    @ObservationIgnored private weak var library: LibraryStore?

    var fsrs: FSRS { FSRS(FSRSParameters(desiredRetention: desiredRetention)) }

    // MARK: Loading

    func load(from library: LibraryStore) async {
        self.library = library
        guard let store = library.fileStore else { return }
        if let settings = try? await store.readJSON(LibrarySettings.self, at: store.url(LibraryLayout.settingsFile)) {
            newPerDay = settings.newCardsPerDay
            desiredRetention = settings.desiredRetention
        }
        var all: [Card] = []
        deckFiles = [:]
        schedulers = [:]
        for course in library.manifest.courses {
            guard let url = library.deckURL(course) else { continue }
            let folder = url.deletingLastPathComponent()
            var deck = (try? await store.readJSON(DeckFile.self, at: url)) ?? DeckFile(courseID: course.id, cards: [])
            // iCloud conflict copies (cards 2.json): merge card by card, then delete the copy.
            for item in (try? await store.listDirectory(folder)) ?? [] where DeckMerge.isConflictCopy(fileName: item.lastPathComponent) {
                if let other = try? await store.readJSON(DeckFile.self, at: item) {
                    deck = DeckMerge.merge(deck, other)
                    try? await store.moveToTrash(item)
                    deckFiles[course.id] = deck
                    try? await store.writeJSON(deck, to: url)
                }
            }
            for i in deck.cards.indices where deck.cards[i].courseID != course.id { deck.cards[i].courseID = course.id }
            deckFiles[course.id] = deck
            schedulers[course.id] = deck.scheduler
            all += deck.cards
        }
        cards = all
        await loadReviews(store)
        loaded = true
    }

    private func loadReviews(_ store: FileStore) async {
        var all: [ReviewEntry] = []
        let root = store.url(LibraryLayout.reviewsDir)
        for dir in (try? await store.listDirectory(root)) ?? [] where await store.isDirectory(dir) {
            for file in (try? await store.listDirectory(dir)) ?? [] where file.pathExtension == "jsonl" {
                if let data = try? await store.readData(at: file) {
                    all += JSONCoding.decodeLines(ReviewEntry.self, from: data)
                }
            }
        }
        entries = all
        recompute()
    }

    private func recompute() {
        let courseOf = Dictionary(cards.map { ($0.id, $0.courseID) }, uniquingKeysWith: { a, _ in a })
        let base = fsrs
        let deckParams = schedulers
        let retention = desiredRetention
        states = base.replay(entries, parameters: { cardID in
            guard let course = courseOf[cardID], let s = deckParams[course], let w = s.fsrsParams else { return nil }
            return FSRSParameters(weights: w, desiredRetention: s.desiredRetention ?? retention)
        })
    }

    func state(of card: Card) -> CardSchedule { states[card.id] ?? .new }

    func cards(in courseID: UUID?) -> [Card] {
        let live = cards.filter { !$0.isDeleted }
        guard let courseID else { return live }
        return live.filter { $0.courseID == courseID }
    }

    // MARK: Editing

    func save(_ card: Card) async {
        var card = card
        card.updatedAt = Date()
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card } else { cards.append(card) }
        await writeDeck(card.courseID)
    }

    func delete(_ card: Card) async {
        var c = card
        c.deletedAt = Date()
        c.updatedAt = Date()
        await save(c)
    }

    private func writeDeck(_ courseID: UUID) async {
        guard let library, let store = library.fileStore, let course = library.manifest.course(courseID),
              let url = library.deckURL(course) else { return }
        var deck = deckFiles[courseID] ?? DeckFile(courseID: courseID, cards: [])
        deck.cards = DeckMerge.purgeTombstones(cards.filter { $0.courseID == courseID })
        deckFiles[courseID] = deck
        do { try await store.writeJSON(deck, to: url) } catch {
            AppLog.shared.error("Saving deck for \(course.name) failed: \(error)")
        }
    }

    // MARK: Reviewing

    func queue(scope: ReviewScope, now: Date = Date()) -> [Card] {
        guard let library else { return [] }
        let term = library.currentTerm
        let pool = scope == .all ? cards : cards.filter { if case .course(let id) = scope { return $0.courseID == id } else { return true } }
        let q = ReviewQueue(fsrs: fsrs, now: now)
        let remaining = newPerDay - q.newIntroducedToday(states)
        return q.build(cards: pool, states: states, newLimit: remaining, allowsNew: { [library] card in
            if case .course = scope { return true }
            return library.manifest.course(card.courseID)?.term == term
        })
    }

    func counts(scope: ReviewScope, now: Date = Date()) -> ReviewQueue.Counts {
        guard let library else { return .init() }
        let term = library.currentTerm
        let pool = cards.filter { if case .course(let id) = scope { return $0.courseID == id } else { return true } }
        let q = ReviewQueue(fsrs: fsrs, now: now)
        return q.counts(cards: pool, states: states, newLimit: newPerDay - q.newIntroducedToday(states), allowsNew: { [library] card in
            if case .course = scope { return true }
            return library.manifest.course(card.courseID)?.term == term
        })
    }

    func nextDue(now: Date = Date()) -> Date? {
        ReviewQueue(fsrs: fsrs, now: now).nextDue(cards: cards, states: states)
    }

    /// Grades a card: appends one line to this install's log and updates the derived state.
    @discardableResult
    func grade(_ card: Card, rating: Rating, ms: Int, session: UUID, at now: Date = Date()) async -> ReviewEntry {
        let entry = ReviewEntry(card: card.id, t: now, rating: rating, ms: ms, session: session,
                                kind: state(of: card).isNew ? .learn : (state(of: card).phase == .review ? .review : .relearn),
                                source: "app")
        await append(entry)
        return entry
    }

    func undo(_ entry: ReviewEntry) async {
        await append(.undo(of: entry))
    }

    private func append(_ entry: ReviewEntry) async {
        entries.append(entry)
        recompute()
        guard let library, let store = library.fileStore, let url = library.reviewLogURL(for: entry.t) else { return }
        do {
            try await store.append(JSONCoding.encodeLine(entry), to: url)
        } catch {
            AppLog.shared.error("Appending review failed: \(error)")
        }
    }

    // MARK: Media

    func mediaFolder(for courseID: UUID) -> URL? {
        guard let library, let course = library.manifest.course(courseID) else { return nil }
        return library.courseFolderURL(course)?.appendingPathComponent(LibraryLayout.cardsMediaDir)
    }

    // MARK: Stats

    /// Graded reviews that count (no undone, cram or non-review lines).
    var effectiveReviews: [ReviewEntry] {
        FSRS.effective(entries).filter { $0.rating != nil && $0.kind != .cram }
    }
}
