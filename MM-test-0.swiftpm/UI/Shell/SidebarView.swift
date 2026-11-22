import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Binding var selection: SidebarItem?
    @State private var showingAddCourses = false
    @State private var expanded: Set<TermName> = []
    @State private var didSetExpanded = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Today", systemImage: "sun.max").tag(SidebarItem.today)
                Label("Cards", systemImage: "rectangle.on.rectangle.angled").tag(SidebarItem.cards)
                Label("Search", systemImage: "magnifyingglass").tag(SidebarItem.search)
                Label("Inbox", systemImage: "tray").tag(SidebarItem.inbox)
            }

            ForEach(TermName.allCases, id: \.self) { term in
                Section(isExpanded: expandedBinding(term)) {
                    let courses = library.manifest.courses(in: term)
                    ForEach(courses) { course in
                        CourseRow(course: course)
                            .tag(SidebarItem.course(course.id))
                    }
                    if courses.isEmpty {
                        Button {
                            showingAddCourses = true
                        } label: {
                            Label("Add courses", systemImage: "plus.circle")
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                } header: {
                    Text(termHeader(term))
                }
            }

            Section("Library") {
                Label("All documents", systemImage: "doc.on.doc").tag(SidebarItem.allDocuments)
                Label("Notebooks", systemImage: "book.closed").tag(SidebarItem.notebooks)
                Label("Example sheets", systemImage: "list.number").tag(SidebarItem.exampleSheets)
            }

            Section {
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MathsMaster")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCourses = true
                } label: {
                    Label("Add courses", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCourses) {
            AddCoursesSheet()
        }
        .onAppear {
            if !didSetExpanded {
                expanded = [library.currentTerm]
                didSetExpanded = true
            }
        }
    }

    private func expandedBinding(_ term: TermName) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(term) },
            set: { isOn in
                if isOn { expanded.insert(term) } else { expanded.remove(term) }
            }
        )
    }

    private func termHeader(_ term: TermName) -> String {
        if let year = library.manifest.currentYear?.term(term)?.start.year {
            return "\(term.displayName) \(year)"
        }
        return term.displayName
    }
}

struct CourseRow: View {
    let course: Course

    var body: some View {
        Label {
            Text(course.name)
        } icon: {
            Circle()
                .fill(course.colour.color)
                .frame(width: 11, height: 11)
        }
    }
}
