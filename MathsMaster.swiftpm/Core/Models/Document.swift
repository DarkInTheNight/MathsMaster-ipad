import Foundation

enum DocumentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case lectureNotes, exampleSheet, notebook

    var displayName: String {
        switch self {
        case .lectureNotes: return "Lecture notes"
        case .exampleSheet: return "Example sheet"
        case .notebook: return "Notebook"
        }
    }
}

/// `document.json`: the page list of one document (design plan §3.1, §7.2).
///
/// Where it lives:
/// - lecture notes: `Lecture notes/<name>.pdf.ink/document.json` next to `<name>.pdf`
/// - example sheet: `Example sheets/<name>.sheet/document.json` next to `<name>.pdf` (the questions)
/// - notebook:      `Notebooks/<name>.mmnote/document.json`
/// Ink for each page lives beside it in `pages/<pageID>.drawing` (one PKDrawing per page).
struct DocumentManifest: Codable, Hashable, Identifiable, Sendable {
    static let currentSchema = 1

    var schemaVersion: Int = DocumentManifest.currentSchema
    var id: UUID
    var kind: DocumentKind
    var title: String
    /// File name of the source PDF in the same folder as the sidecar/package
    /// (lecture notes: the notes; example sheet: the question sheet). Nil for notebooks.
    var sourcePDF: String?
    var pages: [Page]
    var bookmarks: [Bookmark] = []
    var tags: [String] = []
    var lastPosition: PagePosition?
    /// Example sheets only.
    var sheet: ExampleSheetInfo?
    var createdAt: Date
    var updatedAt: Date

    static func notebook(title: String, template: PageTemplate = .default, pageCount: Int = 1, now: Date = Date()) -> DocumentManifest {
        DocumentManifest(
            id: UUID(), kind: .notebook, title: title, sourcePDF: nil,
            pages: (0..<max(1, pageCount)).map { _ in Page(background: .template(template)) },
            createdAt: now, updatedAt: now
        )
    }
}

struct Page: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var size: PageSize = .a4Portrait
    var background: PageBackground
    /// Example-sheet answers: which question this page answers.
    var question: Int?
}

struct PageSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double
    /// A4 portrait in points (1 pt = 1/72 in).
    static let a4Portrait = PageSize(width: 595.276, height: 841.89)
    static let a4Landscape = PageSize(width: 841.89, height: 595.276)
}

enum PageBackground: Codable, Hashable, Sendable {
    /// A page of a PDF. `path` is relative to the library root.
    case pdf(path: String, pageIndex: Int)
    case template(PageTemplate)
}

struct PageTemplate: Codable, Hashable, Sendable {
    var kind: TemplateKind
    var spacingMM: Double
    var paper: PaperColour

    static let `default` = PageTemplate(kind: .dotGrid, spacingMM: 5, paper: .white)
    static let answerSheet = PageTemplate(kind: .answerSheet, spacingMM: 5, paper: .white)
}

enum TemplateKind: String, Codable, CaseIterable, Hashable, Sendable {
    case blank, dotGrid, squared, ruled, answerSheet

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .dotGrid: return "Dot grid"
        case .squared: return "Squared"
        case .ruled: return "Ruled"
        case .answerSheet: return "Answer sheet"
        }
    }
}

enum PaperColour: String, Codable, CaseIterable, Hashable, Sendable {
    case white, cream, dark
}

struct Bookmark: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var pageID: UUID
    /// Set when the bookmark marks the start of a lecture ("Lecture 16").
    var lecture: Int?
}

struct PagePosition: Codable, Hashable, Sendable {
    var pageID: UUID
    var zoom: Double
}

/// A place in a document: a page, optionally a rectangle on it (page coordinates, points).
struct Anchor: Codable, Hashable, Sendable {
    var documentID: UUID
    var pageID: UUID
    var rect: Rect?
}

struct Rect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ExampleSheetInfo: Codable, Hashable, Sendable {
    var questions: [SheetQuestion] = []
    var supervisionDate: CalendarDate?
    var handInDate: CalendarDate?

    var stuckCount: Int { questions.filter { $0.status == .stuck }.count }
    var doneCount: Int { questions.filter { $0.status == .done }.count }
}

struct SheetQuestion: Codable, Hashable, Identifiable, Sendable {
    var id: Int { number }
    var number: Int
    var status: QuestionStatus = .notStarted
}

enum QuestionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case notStarted, attempted, done, stuck
}
