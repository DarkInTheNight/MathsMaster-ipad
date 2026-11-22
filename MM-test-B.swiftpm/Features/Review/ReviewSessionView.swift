import SwiftUI
import PencilKit

/// Full-screen review (design plan §4.3): front, a writing area, reveal with the attempt beside
/// the answer, then the grade buttons.
struct ReviewSessionView: View {
    let scope: ReviewScope

    @Environment(CardStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var started = false
    @State private var revealed = false
    @State private var drawing = PKDrawing()
    @State private var undoTrigger = 0
    @State private var shownAt = Date()
    @State private var session = UUID()
    @State private var done: [ReviewEntry] = []
    @State private var graded: [(Card, ReviewEntry, Int)] = []   // for undo: card, entry, queue index
    @State private var sideBySide = true
    @State private var section: Int?
    @State private var editing: Card?
    @State private var showEndConfirm = false

    private var current: Card? { index < queue.count ? queue[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let card = current {
                cardArea(card)
            } else if started {
                summary
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !started else { return }
            queue = store.queue(scope: scope)
            started = true
            shownAt = Date()
        }
        .sheet(item: $editing) { card in
            CardEditorView(card: card) { _ in }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { dismiss() } label: { Label("End", systemImage: "xmark") }
                Text(scopeName).font(.headline)
                Spacer()
                countsLabel
                Button { Task { await undoLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(graded.isEmpty)
            }
            ProgressView(value: Double(min(index, queue.count)), total: Double(max(queue.count, 1)))
                .tint(Theme.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    private var scopeName: String {
        switch scope {
        case .all: return "All courses"
        case .course(let id): return library.manifest.course(id)?.name ?? "Course"
        }
    }

    private var countsLabel: some View {
        let rest = queue.dropFirst(index)
        let n = rest.filter { store.state(of: $0).isNew }.count
        let l = rest.filter { store.state(of: $0).isLearning }.count
        return Text("New \(n) · Learning \(l) · Review \(rest.count - n - l)")
            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink2)
    }

    // MARK: Card

    private func cardArea(_ card: Card) -> some View {
        let media = store.mediaFolder(for: card.courseID)
        return GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let compare = revealed && (landscape || sideBySide)
            VStack(spacing: 0) {
                frontPane(card, media: media)
                    .frame(height: min(max(geo.size.height * 0.22, 120), 240))
                Divider()
                ZStack(alignment: .bottom) {
                    Group {
                        if !revealed {
                            AttemptCanvas(drawing: $drawing, undoTrigger: undoTrigger)
                        } else if compare {
                            HStack(spacing: 0) {
                                AttemptCanvas(drawing: $drawing, undoTrigger: undoTrigger)
                                Divider()
                                answerPane(card, media: media)
                            }
                        } else {
                            VStack(spacing: 0) {
                                AttemptCanvas(drawing: $drawing, undoTrigger: undoTrigger).frame(height: geo.size.height * 0.28)
                                Divider()
                                answerPane(card, media: media)
                            }
                        }
                    }
                    bottomBar(card, portrait: !landscape)
                }
            }
        }
    }

    private func frontPane(_ card: Card, media: URL?) -> some View {
        ZStack(alignment: .topTrailing) {
            CardWebView(html: card.front, mediaFolder: media, fontSize: 24)
            Text(card.label.displayName).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent).padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !revealed { reveal() } }
    }

    private func answerPane(_ card: Card, media: URL?) -> some View {
        VStack(spacing: 0) {
            let sections = CardText.sections(in: card.back)
            if !sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(sections.enumerated()), id: \.offset) { i, title in
                            Button(title) { section = i }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            CardWebView(html: card.back, mediaFolder: media, scrollToSection: section)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom bar

    private func bottomBar(_ card: Card, portrait: Bool) -> some View {
        HStack(spacing: 12) {
            if !revealed {
                Button { drawing = PKDrawing() } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                Button { undoTrigger += 1 } label: { Image(systemName: "arrow.uturn.backward.circle") }.buttonStyle(.bordered)
                Spacer()
                Button { reveal() } label: { Label("Show answer", systemImage: "eye").padding(.horizontal, 12) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.space, modifiers: [])
            } else {
                Button { editing = card } label: { Image(systemName: "pencil") }.buttonStyle(.bordered)
                Button { Task { var c = card; c.flagged.toggle(); await store.save(c); replace(c) } } label: {
                    Image(systemName: card.flagged ? "flag.fill" : "flag")
                }.buttonStyle(.bordered)
                if portrait {
                    Button { sideBySide.toggle() } label: { Image(systemName: "rectangle.split.2x1") }.buttonStyle(.bordered)
                }
                Spacer()
                gradeButtons(card)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)
    }

    private func gradeButtons(_ card: Card) -> some View {
        let outcomes = store.fsrs.outcomes(for: store.state(of: card), at: Date())
        return HStack(spacing: 8) {
            ForEach(Rating.allCases, id: \.self) { rating in
                Button { Task { await grade(card, rating) } } label: {
                    VStack(spacing: 2) {
                        Text(rating.label).font(.headline)
                        Text(outcomes[rating].map(intervalText) ?? "").font(.caption)
                    }
                    .frame(minWidth: 78).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(color(rating))
                .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
            }
        }
    }

    private func color(_ r: Rating) -> Color {
        switch r { case .again: return Theme.again; case .hard: return Theme.hard; case .good: return Theme.good; case .easy: return Theme.easy }
    }

    private func intervalText(_ s: CardSchedule) -> String {
        guard let due = s.due else { return "" }
        let seconds = due.timeIntervalSinceNow
        if seconds < 3600 { return "\(max(1, Int((seconds / 60).rounded())))m" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded()))h" }
        let days = Int((seconds / 86_400).rounded())
        if days < 30 { return "\(days)d" }
        if days < 365 { return String(format: "%.1fmo", Double(days) / 30.4) }
        return String(format: "%.1fy", Double(days) / 365)
    }

    // MARK: Actions

    private func reveal() {
        withAnimation(.snappy) { revealed = true }
        section = nil
    }

    private func replace(_ card: Card) {
        if let i = queue.firstIndex(where: { $0.id == card.id }) { queue[i] = card }
    }

    private func grade(_ card: Card, _ rating: Rating) async {
        let ms = Int(Date().timeIntervalSince(shownAt) * 1000)
        let entry = await store.grade(card, rating: rating, ms: ms, session: session)
        done.append(entry)
        graded.append((card, entry, index))
        // A card still in a learning step comes back later in this session.
        let s = store.state(of: card)
        if s.isLearning, let due = s.due, due < Date().addingTimeInterval(ReviewQueue.learnAhead) {
            queue.append(card)
        }
        advance()
    }

    private func advance() {
        index += 1
        revealed = false
        drawing = PKDrawing()
        shownAt = Date()
        section = nil
    }

    private func undoLast() async {
        guard let last = graded.popLast() else { return }
        await store.undo(last.1)
        done.removeAll { $0.id == last.1.id }
        // Remove the re-queued copy, if any, and go back.
        if queue.count > index, queue.last?.id == last.0.id, last.2 != queue.count - 1 { queue.removeLast() }
        index = last.2
        revealed = false
        drawing = PKDrawing()
        shownAt = Date()
    }

    // MARK: End card

    private var summary: some View {
        let seconds = done.reduce(0) { $0 + $1.ms } / 1000
        let again = done.filter { $0.rating == .again }.count
        let retained = done.isEmpty ? 0 : Int((Double(done.count - again) / Double(done.count) * 100).rounded())
        return VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.good)
            Text(done.isEmpty ? "Nothing due" : "Session complete").font(.largeTitle.bold())
            if !done.isEmpty {
                Text("\(done.count) cards · \(seconds / 60) min \(seconds % 60) s · \(retained)% remembered")
                    .font(.title3).foregroundStyle(Theme.ink2)
            }
            let tomorrow = store.counts(scope: scope, now: Date().addingTimeInterval(86_400))
            Text("Due tomorrow: \(tomorrow.review + tomorrow.learning)").foregroundStyle(Theme.ink2)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
