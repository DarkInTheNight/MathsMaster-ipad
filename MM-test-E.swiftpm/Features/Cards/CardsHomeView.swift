import SwiftUI

/// Sidebar → Cards: decks, review-all, browser and stats.
struct CardsHomeView: View {
    @Environment(CardStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ReviewHeroCard()
                Text("Decks").font(.title2.bold())
                let courses = library.manifest.courses.filter { !$0.archived }
                if courses.isEmpty {
                    Panel { Text("Add courses first; each course gets a deck.").foregroundStyle(Theme.ink2) }
                }
                ForEach(courses) { course in
                    Panel {
                        HStack {
                            Circle().fill(course.colour.color).frame(width: 12, height: 12)
                            VStack(alignment: .leading) {
                                Text(course.name).font(.headline)
                                let n = store.cards(in: course.id).count
                                let c = store.counts(scope: .course(course.id))
                                Text("\(n) cards · \(c.review + c.learning) due · \(c.new) new").foregroundStyle(Theme.ink2)
                            }
                            Spacer()
                            Button("Browse") { openRoute(.cardBrowser(courseID: course.id)) }.buttonStyle(.bordered)
                            Button("Review") { openRoute(.review(.course(course.id))) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                HStack {
                    Button { openRoute(.cardBrowser(courseID: nil)) } label: { Label("All cards", systemImage: "list.bullet.rectangle") }
                    NavigationLink { StatsView() } label: { Label("Statistics", systemImage: "chart.bar") }
                }.buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Cards")
    }
}

/// The Cards shelf on a course page.
struct CourseDeckSummaryView: View {
    let course: Course
    @Environment(CardStore.self) private var store
    @Environment(\.openRoute) private var openRoute
    @State private var newCard: Card?

    var body: some View {
        Panel {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.title2).foregroundStyle(course.colour.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(course.name) deck").font(.headline)
                    let c = store.counts(scope: .course(course.id))
                    Text("\(store.cards(in: course.id).count) cards · \(c.review + c.learning) due · \(c.new) new")
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button { newCard = Card.new(courseID: course.id, front: "", back: "") } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Button("Browse") { openRoute(.cardBrowser(courseID: course.id)) }.buttonStyle(.bordered)
            }
        }
        .sheet(item: $newCard) { card in CardEditorView(card: card) { _ in } }
    }
}

/// Searchable list of cards, with edit, flag, suspend and delete.
struct CardBrowserView: View {
    let courseID: UUID?
    @Environment(CardStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @State private var search = ""
    @State private var editing: Card?
    @State private var filter: Filter = .all
    enum Filter: String, CaseIterable { case all = "All", flagged = "Flagged", suspended = "Suspended", new = "New" }

    private var shown: [Card] {
        store.cards(in: courseID).filter { card in
            switch filter {
            case .all: break
            case .flagged: if !card.flagged { return false }
            case .suspended: if !card.suspended { return false }
            case .new: if !store.state(of: card).isNew { return false }
            }
            guard !search.isEmpty else { return true }
            return card.front.localizedCaseInsensitiveContains(search) || card.back.localizedCaseInsensitiveContains(search)
                || card.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Picker("Filter", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            ForEach(shown) { card in
                Button { editing = card } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(card.label.displayName).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                            if card.flagged { Image(systemName: "flag.fill").foregroundStyle(Theme.hard) }
                            if card.suspended { Image(systemName: "pause.circle").foregroundStyle(Theme.ink2) }
                            Spacer()
                            Text(library.manifest.course(card.courseID)?.name ?? "").font(.caption).foregroundStyle(Theme.ink2)
                        }
                        Text(CardText.plainPreview(card.front)).font(.headline).lineLimit(2)
                        Text(CardText.plainPreview(card.back)).font(.subheadline).foregroundStyle(Theme.ink2).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { Task { await store.delete(card) } } label: { Label("Delete", systemImage: "trash") }
                    Button { Task { var c = card; c.suspended.toggle(); await store.save(c) } } label: { Label("Suspend", systemImage: "pause") }
                    Button { Task { var c = card; c.flagged.toggle(); await store.save(c) } } label: { Label("Flag", systemImage: "flag") }.tint(Theme.hard)
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(courseID.flatMap { library.manifest.course($0)?.name } ?? "All cards")
        .toolbar {
            Button { editing = Card.new(courseID: courseID ?? library.manifest.courses.first?.id ?? UUID(), front: "", back: "") } label: {
                Label("New card", systemImage: "plus")
            }
            .disabled(library.manifest.courses.isEmpty)
        }
        .sheet(item: $editing) { card in CardEditorView(card: card) { _ in } }
    }
}

/// The Review block at the top of Today (design plan §2.3).
struct ReviewHeroCard: View {
    @Environment(CardStore.self) private var store
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        let c = store.counts(scope: .all)
        let streak = Stats.streak(reviews: store.effectiveReviews)
        Panel {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REVIEW").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.accent)
                    if c.total == 0 {
                        Text("All done").font(.title2.bold())
                        Text(nextDueText).foregroundStyle(Theme.ink2)
                    } else {
                        Text("\(c.review + c.learning) due · \(c.new) new").font(.title2.bold())
                        Text("About \(max(1, c.total * 2)) min").foregroundStyle(Theme.ink2)
                    }
                    if streak > 0 { Label("\(streak)-day streak", systemImage: "flame.fill").font(.subheadline).foregroundStyle(Theme.hard) }
                }
                Spacer()
                NavigationLink { StatsView() } label: { Image(systemName: "chart.bar") }.buttonStyle(.bordered)
                Button { openRoute(.review(.all)) } label: {
                    Label("Start review", systemImage: "play.fill").padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(c.total == 0)
            }
        }
    }

    private var nextDueText: String {
        guard let next = store.nextDue() else { return "No cards scheduled yet. Add cards in a course." }
        return "Next due " + next.formatted(.relative(presentation: .named))
    }
}
