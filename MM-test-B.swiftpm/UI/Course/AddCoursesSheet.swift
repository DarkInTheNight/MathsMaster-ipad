import SwiftUI

/// Pick courses from the Part IB list, or add a custom one.
struct AddCoursesSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var customName = ""
    @State private var customTerm: TermName = .michaelmas
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(TermName.allCases, id: \.self) { term in
                    Section("\(term.displayName) · Part IB") {
                        ForEach(CourseTemplate.partIB.filter { $0.term == term }) { template in
                            let exists = library.manifest.courses.contains { $0.name == template.name && !$0.archived }
                            Toggle(isOn: binding(for: template.name, exists: exists)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                    if let lectures = template.lectures {
                                        Text("\(lectures) lectures").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(exists)
                        }
                    }
                }
                Section {
                    TextField("Course name", text: $customName)
                    Picker("Term", selection: $customTerm) {
                        ForEach(TermName.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Another course")
                } footer: {
                    Text("Each course gets its own folder in your library, with Lecture notes, Example sheets and Notebooks inside.")
                }
            }
            .navigationTitle("Add courses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        Task {
                            await add()
                            dismiss()
                        }
                    }
                    .disabled(saving || (selected.isEmpty && trimmedName.isEmpty))
                }
            }
        }
    }

    private var trimmedName: String { customName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func binding(for name: String, exists: Bool) -> Binding<Bool> {
        Binding(
            get: { exists || selected.contains(name) },
            set: { isOn in
                if isOn { selected.insert(name) } else { selected.remove(name) }
            }
        )
    }

    private func add() async {
        let templates = CourseTemplate.partIB.filter { selected.contains($0.name) }
        if !templates.isEmpty {
            await library.addCourses(from: templates)
        }
        if !trimmedName.isEmpty {
            await library.addCourse(name: trimmedName, term: customTerm)
        }
    }
}
