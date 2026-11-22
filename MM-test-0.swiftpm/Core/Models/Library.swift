import Foundation

/// `library.json` at the root of the library folder: the list of years, terms and courses.
struct LibraryManifest: Codable, Hashable, Sendable {
    static let currentSchema = 1

    var schemaVersion: Int = LibraryManifest.currentSchema
    var libraryID: UUID
    var name: String
    var years: [AcademicYear]
    var courses: [Course]
    var createdAt: Date

    /// The year new courses go into by default (the latest one).
    var currentYear: AcademicYear? { years.last }

    func courses(in term: TermName, yearID: UUID? = nil) -> [Course] {
        courses
            .filter { $0.term == term && !$0.archived && (yearID == nil || $0.yearID == yearID) }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    /// A fresh library with one academic year and its three terms.
    static func makeNew(name: String = "MathsMaster", year: AcademicYear = .partIB2026, now: Date = Date()) -> LibraryManifest {
        LibraryManifest(libraryID: UUID(), name: name, years: [year], courses: [], createdAt: now)
    }
}

struct AcademicYear: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var terms: [Term]

    func term(_ name: TermName) -> Term? { terms.first { $0.name == name } }

    /// Part IB 2026–27 with Full Term dates (editable in Settings).
    static var partIB2026: AcademicYear {
        AcademicYear(
            id: UUID(),
            name: "Part IB 2026–27",
            terms: [
                Term(name: .michaelmas, start: CalendarDate(year: 2026, month: 10, day: 6), end: CalendarDate(year: 2026, month: 12, day: 4)),
                Term(name: .lent, start: CalendarDate(year: 2027, month: 1, day: 19), end: CalendarDate(year: 2027, month: 3, day: 19)),
                Term(name: .easter, start: CalendarDate(year: 2027, month: 4, day: 27), end: CalendarDate(year: 2027, month: 6, day: 18)),
            ]
        )
    }
}

enum TermName: String, Codable, CaseIterable, Hashable, Sendable {
    case michaelmas, lent, easter

    var displayName: String {
        switch self {
        case .michaelmas: return "Michaelmas"
        case .lent: return "Lent"
        case .easter: return "Easter"
        }
    }
}

/// Full Term dates (Cambridge Full Term starts on a Tuesday).
struct Term: Codable, Hashable, Sendable {
    var name: TermName
    var start: CalendarDate
    var end: CalendarDate
}

struct Course: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var yearID: UUID
    var term: TermName
    var colour: CourseColour
    /// Folder relative to the library root, e.g. "Courses/Linear Algebra".
    var folder: String
    var lectures: Int?
    var examDate: CalendarDate?
    var order: Int
    var archived: Bool = false
}

/// The 12 course colours (design plan §6.3). Hex values are sRGB.
enum CourseColour: String, Codable, CaseIterable, Hashable, Sendable {
    case indigo, teal, amber, coral, violet, sky, green, rose, slate, orange, olive, plum

    var hex: UInt32 {
        switch self {
        case .indigo: return 0x5B6CF0
        case .teal: return 0x1F9E8F
        case .amber: return 0xD69A00
        case .coral: return 0xE0645A
        case .violet: return 0x9A5BD8
        case .sky: return 0x2F9BDB
        case .green: return 0x4AA35A
        case .rose: return 0xD9578A
        case .slate: return 0x5F7389
        case .orange: return 0xE07B2E
        case .olive: return 0x8C9A2E
        case .plum: return 0x8E4F7A
        }
    }

    /// First colour not yet used by `existing`, cycling if all are taken.
    static func next(after existing: [CourseColour]) -> CourseColour {
        allCases.first { !existing.contains($0) } ?? allCases[existing.count % allCases.count]
    }
}

/// `course.json` inside each course folder. Lets the app re-link a folder to its course
/// if `library.json` is lost or edited by hand.
struct CourseFile: Codable, Hashable, Sendable {
    static let currentSchema = 1
    var schemaVersion: Int = CourseFile.currentSchema
    var id: UUID
    var name: String
    var ankiDeckName: String?
}
