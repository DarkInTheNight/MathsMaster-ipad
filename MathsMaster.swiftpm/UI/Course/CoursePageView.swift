import SwiftUI
import UniformTypeIdentifiers

/// A course's home: header, then the four shelves (design plan §2.4).
struct CoursePageView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openRoute) private var openRoute
    let course: Course

    @State private var importKind: DocumentKind = .lectureNotes
    @State private var showingImporter = false
    @State private var showingNewNotebook = false
    @State private var newNotebookTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                shelf(.lectureNotes, empty: "Import the lecture notes PDF for this course.")
                shelf(.exampleSheet, empty: "Import example sheet PDFs. Each gets an answers notebook.")
                shelf(.notebook, empty: "Blank, dotted, squared or ruled pages for your own notes.")
                cardsShelf
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openRoute(.review(.course(course.id)))
                } label: {
                    Label("Review this course", systemImage: "rectangle.on.rectangle.angled")
                }
                addMenu
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let kind = importKind
                Task { await library.importPDFs(urls, into: course, kind: kind) }
            case .failure(let error):
                AppLog.shared.error("PDF picker failed: \(error.localizedDescription)")
            }
        }
        .alert("New notebook", isPresented: $showingNewNotebook) {
            TextField("Title", text: $newNotebookTitle)
            Button("Create") {
                let title = newNotebookTitle
                newNotebookTitle = ""
                Task {
                    if let document = await library.createNotebook(in: course, title: title) {
                        openRoute(.document(document))
                    }
                }
            }
            Button("Cancel", role: .cancel) { newNotebookTitle = "" }
        }
        .refreshable { await library.rescan(course) }
        .task(id: course.id) { await library.rescan(course) }
    }

    private var addMenu: some View {
        Menu {
            Button {
                importKind = .lectureNotes
                showingImporter = true
            } label: {
                Label("Import lecture notes…", systemImage: "doc.richtext")
            }
            Button {
                importKind = .exampleSheet
                showingImporter = true
            } label: {
                Label("Import example sheet…", systemImage: "list.number")
            }
            Button {
                showingNewNotebook = true
            } label: {
                Label("New notebook", systemImage: "square.and.pencil")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(course.colour.color).frame(width: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(subtitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(course.colour.color)
                Text(course.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                Text(progressLine)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(course.colour.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var subtitle: String {
        var parts = [course.term.displayName]
        if let year = library.manifest.currentYear?.term(course.term)?.start.year { parts[0] += " \(year)" }
        if let lectures = course.lectures { parts.append("\(lectures) lectures") }
        return parts.joined(separator: " · ")
    }

    private var progressLine: String {
        let notes = library.documents(in: course, kind: .lectureNotes).count
        let sheets = library.documents(in: course, kind: .exampleSheet).count
        let notebooks = library.documents(in: course, kind: .notebook).count
        return "\(notes) lecture notes · \(sheets) example sheets · \(notebooks) notebooks"
    }

    @ViewBuilder
    private func shelf(_ kind: DocumentKind, empty: String) -> some View {
        let documents = library.documents(in: course, kind: kind)
        VStack(alignment: .leading, spacing: 14) {
            Text(shelfTitle(kind)).font(.title2.bold())
            if documents.isEmpty {
                Button {
                    if kind == .notebook {
                        showingNewNotebook = true
                    } else {
                        importKind = kind
                        showingImporter = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind == .notebook ? "square.and.pencil" : "square.and.arrow.down")
                            .font(.title2)
                        Text(empty).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                DocumentGrid(documents: documents) { _ in course.colour.color }
            }
        }
    }

    private func shelfTitle(_ kind: DocumentKind) -> String {
        switch kind {
        case .lectureNotes: return "Lecture notes"
        case .exampleSheet: return "Example sheets"
        case .notebook: return "Notebooks"
        }
    }

    private var cardsShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cards").font(.title2.bold())
            CourseDeckSummaryView(course: course)
        }
    }
}
