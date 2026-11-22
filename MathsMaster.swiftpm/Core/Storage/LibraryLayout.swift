import Foundation

/// Folder and file names inside the library folder (design plan §7.2).
/// Pure path logic; all I/O goes through `FileStore`.
enum LibraryLayout {
    static let manifestFile = "library.json"
    static let settingsFile = "settings.json"
    static let devicesFile = "devices.json"
    static let coursesDir = "Courses"
    static let reviewsDir = "Reviews"
    static let inboxDir = "Inbox"
    static let importDir = "Inbox/Import"
    static let jobsDir = "Inbox/jobs"
    static let exportsDir = "Exports"
    static let logsDir = "Logs"
    static let aiDir = "AI"
    static let cardGuidelinesFile = "AI/card-guidelines.md"
    static let trashDir = ".trash"

    // Inside a course folder
    static let courseFile = "course.json"
    static let deckFile = "cards.json"
    static let cardsMediaDir = "cards-media"
    static let threadsDir = "threads"
    static let attemptsDir = "attempts"
    static let aiInstructionsFile = "ai-instructions.md"

    // Documents
    static let documentManifestFile = "document.json"
    static let pagesDir = "pages"
    static let pdfSidecarSuffix = ".ink"
    static let notebookExtension = "mmnote"
    static let sheetExtension = "sheet"
    static let drawingExtension = "drawing"

    /// Top-level folders created in a new library.
    static let standardDirectories = [coursesDir, reviewsDir, importDir, jobsDir, exportsDir, logsDir, aiDir, trashDir]

    /// The three shelves of a course, as folders.
    enum Shelf: String, CaseIterable, Hashable, Sendable {
        case lectureNotes = "Lecture notes"
        case exampleSheets = "Example sheets"
        case notebooks = "Notebooks"

        var kind: DocumentKind {
            switch self {
            case .lectureNotes: return .lectureNotes
            case .exampleSheets: return .exampleSheet
            case .notebooks: return .notebook
            }
        }

        init(kind: DocumentKind) {
            switch kind {
            case .lectureNotes: self = .lectureNotes
            case .exampleSheet: self = .exampleSheets
            case .notebook: self = .notebooks
            }
        }
    }

    static func courseFolder(for name: String) -> String {
        "\(coursesDir)/\(safeFileName(name))"
    }

    /// Sidecar or package folder name that holds `document.json` for a document.
    static func manifestFolderName(kind: DocumentKind, fileName: String) -> String {
        switch kind {
        case .lectureNotes: return fileName + pdfSidecarSuffix                      // "LA notes.pdf.ink"
        case .exampleSheet: return stripExtension(fileName) + "." + sheetExtension   // "Sheet 3.sheet"
        case .notebook: return fileName.hasSuffix("." + notebookExtension) ? fileName : fileName + "." + notebookExtension
        }
    }

    static func pageInkFileName(pageID: UUID) -> String {
        "\(pageID.uuidString).\(drawingExtension)"
    }

    /// `Reviews/<installID>/2026-11.jsonl`
    static func reviewLogPath(installID: String, date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%@/%@/%04d-%02d.jsonl", reviewsDir, installID, c.year ?? 1970, c.month ?? 1)
    }

    /// A name that is safe as a single path component on iOS, Windows (iCloud for Windows) and Linux.
    static func safeFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(120))
    }

    static func stripExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        return String(fileName[..<dot])
    }

    /// iCloud Drive replaces evicted files with hidden placeholders named `.<name>.icloud`.
    /// Returns the real file name for such a placeholder, or nil.
    static func realNameForICloudPlaceholder(_ fileName: String) -> String? {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud"), fileName.count > 8 else { return nil }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }
}
