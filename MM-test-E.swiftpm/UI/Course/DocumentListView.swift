import SwiftUI

/// Library → All documents / Notebooks / Example sheets, grouped by course.
struct DocumentListView: View {
    @Environment(LibraryStore.self) private var library
    let title: String
    let kind: DocumentKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                let courses = library.manifest.courses.filter { !$0.archived }
                ForEach(courses) { course in
                    let documents = (library.documentsByCourse[course.id] ?? []).filter { kind == nil || $0.kind == kind }
                    if !documents.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            CourseRow(course: course).font(.title3.bold())
                            DocumentGrid(documents: documents) { _ in course.colour.color }
                        }
                    }
                }
                if library.allDocuments.filter({ kind == nil || $0.kind == kind }).isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "doc", description: Text("Import PDFs or create notebooks from a course page."))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(title)
    }
}
