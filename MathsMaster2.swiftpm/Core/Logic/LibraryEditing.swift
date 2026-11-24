import Foundation

/// Pure edits on the library manifest (kept out of the UI layer so they can be unit-tested).
extension LibraryManifest {
    /// Adds a course, choosing a colour and a unique folder. Returns the new course.
    @discardableResult
    mutating func addCourse(name: String, term: TermName, lectures: Int? = nil, colour: CourseColour? = nil) -> Course {
        guard let year = currentYear else {
            preconditionFailure("A library always has at least one academic year")
        }
        var folder = LibraryLayout.courseFolder(for: name)
        var suffix = 2
        while courses.contains(where: { $0.folder.lowercased() == folder.lowercased() }) {
            folder = LibraryLayout.courseFolder(for: "\(name) \(suffix)")
            suffix += 1
        }
        let course = Course(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            yearID: year.id,
            term: term,
            colour: colour ?? CourseColour.next(after: courses.filter { !$0.archived }.map(\.colour)),
            folder: folder,
            lectures: lectures,
            order: (courses.filter { $0.term == term }.map(\.order).max() ?? -1) + 1
        )
        courses.append(course)
        return course
    }

    mutating func updateCourse(_ course: Course) {
        guard let i = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[i] = course
    }
}
