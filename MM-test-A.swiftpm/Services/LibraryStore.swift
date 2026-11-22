import Foundation
import Observation

/// A document as listed on a course page. Load the full page list with `LibraryStore.loadManifest(for:)`.
struct DocumentSummary: Identifiable, Hashable {
    let id: UUID
    let courseID: UUID
    let kind: DocumentKind
    let title: String
    /// The PDF (lecture notes, example sheet questions) or the `.mmnote` package (notebooks).
    let fileURL: URL
    /// `…/document.json`
    let manifestURL: URL
    let pageCount: Int
    let updatedAt: Date
    let sheet: ExampleSheetInfo?

    /// The sidecar/package folder; page ink lives in `pages/<pageID>.drawing` inside it.
    var packageURL: URL { manifestURL.deletingLastPathComponent() }
    var pagesURL: URL { packageURL.appendingPathComponent(LibraryLayout.pagesDir) }
}

/// Per-install list of recently opened documents (Today → Continue).
struct RecentLocation: Codable, Hashable, Identifiable {
    var id: UUID { documentID }
    var documentID: UUID
    var courseID: UUID
    var pageIndex: Int?
    var openedAt: Date
}

/// The app's view of the library folder. Owns the manifest and the document index;
/// all writes go through `fileStore`.
@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable {
        case starting, needsFolder, loading, ready
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    private(set) var manifest: LibraryManifest = .makeNew()
    private(set) var documentsByCourse: [UUID: [DocumentSummary]] = [:]
    private(set) var recents: [RecentLocation] = []
    private(set) var rootURL: URL?
    private(set) var fileStore: FileStore?

    @ObservationIgnored private let location = LibraryLocation()
    @ObservationIgnored private let recentsKey = "recentLocations"

    // MARK: Opening

    func start() async {
        if let url = location.resolve() {
            await open(url)
        } else {
            phase = .needsFolder
        }
    }

    func useFolder(_ url: URL) async {
        do {
            try location.save(pickedFolder: url)
            await open(url)
        } catch {
            phase = .failed("Couldn't keep access to that folder: \(error.localizedDescription)")
        }
    }

    func forgetFolder() {
        location.forget()
        rootURL = nil
        fileStore = nil
        documentsByCourse = [:]
        phase = .needsFolder
    }

    func open(_ root: URL) async {
        phase = .loading
        let store = FileStore(root: root)
        fileStore = store
        rootURL = root
        AppLog.shared.attach(store)
        AppLog.shared.info("Opening library at \(root.path)")
        do {
            let manifestURL = store.url(LibraryLayout.manifestFile)
            if await store.exists(manifestURL) {
                manifest = try await store.readJSON(LibraryManifest.self, at: manifestURL)
            } else {
                manifest = .makeNew()
                for dir in LibraryLayout.standardDirectories {
                    try await store.ensureDirectory(store.url(dir))
                }
                try await store.writeJSON(manifest, to: manifestURL)
                AppLog.shared.info("Created a new library")
            }
            await registerDevice()
            loadRecents()
            phase = .ready
            await rescanAll()
        } catch {
            AppLog.shared.error("Opening library failed: \(error)")
            phase = .failed("Couldn't open the library: \(error.localizedDescription)")
        }
    }

    private func registerDevice() async {
        guard let store = fileStore else { return }
        let url = store.url(LibraryLayout.devicesFile)
        var devices = (try? await store.readJSON(DevicesFile.self, at: url)) ?? DevicesFile()
        let name = InstallIdentity.displayName
        if devices.devices[InstallIdentity.id] != name {
            devices.devices[InstallIdentity.id] = name
            try? await store.writeJSON(devices, to: url)
        }
    }

    // MARK: Calendar

    var today: CalendarDate { CalendarDate(Date()) }

    var termPosition: CambridgeCalendar.Position? {
        manifest.currentYear.flatMap { CambridgeCalendar.position(of: today, in: $0) }
    }

    var currentTerm: TermName {
        manifest.currentYear.map { CambridgeCalendar.currentTerm(on: today, in: $0) } ?? .michaelmas
    }

    // MARK: Courses

    func saveManifest() async {
        guard let store = fileStore else { return }
        do {
            try await store.writeJSON(manifest, to: store.url(LibraryLayout.manifestFile))
        } catch {
            AppLog.shared.error("Saving library.json failed: \(error)")
        }
    }

    func addCourses(from templates: [CourseTemplate]) async {
        var added: [Course] = []
        for t in templates where !manifest.courses.contains(where: { $0.name == t.name && !$0.archived }) {
            added.append(manifest.addCourse(name: t.name, term: t.term, lectures: t.lectures))
        }
        await saveManifest()
        for course in added { await createCourseFolder(course) }
        AppLog.shared.info("Added \(added.count) course(s)")
    }

    @discardableResult
    func addCourse(name: String, term: TermName, lectures: Int? = nil, colour: CourseColour? = nil) async -> Course {
        let course = manifest.addCourse(name: name, term: term, lectures: lectures, colour: colour)
        await saveManifest()
        await createCourseFolder(course)
        return course
    }

    func updateCourse(_ course: Course) async {
        manifest.updateCourse(course)
        await saveManifest()
    }

    func courseFolderURL(_ course: Course) -> URL? {
        fileStore?.url(course.folder)
    }

    func shelfURL(_ course: Course, kind: DocumentKind) -> URL? {
        courseFolderURL(course)?.appendingPathComponent(LibraryLayout.Shelf(kind: kind).rawValue)
    }

    /// `Courses/<course>/cards.json` (workstream C).
    func deckURL(_ course: Course) -> URL? {
        courseFolderURL(course)?.appendingPathComponent(LibraryLayout.deckFile)
    }

    /// This install's review log for the month of `date` (workstream C).
    func reviewLogURL(for date: Date = Date()) -> URL? {
        fileStore?.url(LibraryLayout.reviewLogPath(installID: InstallIdentity.id, date: date))
    }

    private func createCourseFolder(_ course: Course) async {
        guard let store = fileStore, let folder = courseFolderURL(course) else { return }
        do {
            for shelf in LibraryLayout.Shelf.allCases {
                try await store.ensureDirectory(folder.appendingPathComponent(shelf.rawValue))
            }
            let file = CourseFile(id: course.id, name: course.name)
            try await store.writeJSON(file, to: folder.appendingPathComponent(LibraryLayout.courseFile))
        } catch {
            AppLog.shared.error("Creating folder for \(course.name) failed: \(error)")
        }
    }

    // MARK: Documents

    var allDocuments: [DocumentSummary] {
        documentsByCourse.values.flatMap { $0 }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func documents(in course: Course, kind: DocumentKind) -> [DocumentSummary] {
        (documentsByCourse[course.id] ?? []).filter { $0.kind == kind }
    }

    func document(_ id: UUID) -> DocumentSummary? {
        documentsByCourse.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    func course(of document: DocumentSummary) -> Course? {
        manifest.course(document.courseID)
    }

    func rescanAll() async {
        for course in manifest.courses where !course.archived {
            await rescan(course)
        }
    }

    /// Re-reads one course folder. PDFs without a sidecar (e.g. added in the Files app) get one.
    func rescan(_ course: Course) async {
        guard let store = fileStore, let folder = courseFolderURL(course) else { return }
        var found: [DocumentSummary] = []
        for shelf in LibraryLayout.Shelf.allCases {
            let dir = folder.appendingPathComponent(shelf.rawValue)
            let items = (try? await store.listDirectory(dir)) ?? []
            switch shelf.kind {
            case .lectureNotes, .exampleSheet:
                for pdf in items where pdf.pathExtension.lowercased() == "pdf" {
                    if let summary = await summaryForPDF(pdf, kind: shelf.kind, course: course, store: store) {
                        found.append(summary)
                    }
                }
            case .notebook:
                for package in items where package.pathExtension == LibraryLayout.notebookExtension {
                    let manifestURL = package.appendingPathComponent(LibraryLayout.documentManifestFile)
                    if let m = try? await store.readJSON(DocumentManifest.self, at: manifestURL) {
                        found.append(summary(m, course: course, fileURL: package, manifestURL: manifestURL))
                    }
                }
            }
        }
        documentsByCourse[course.id] = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func summaryForPDF(_ pdf: URL, kind: DocumentKind, course: Course, store: FileStore) async -> DocumentSummary? {
        let folderName = LibraryLayout.manifestFolderName(kind: kind, fileName: pdf.lastPathComponent)
        let manifestURL = pdf.deletingLastPathComponent()
            .appendingPathComponent(folderName)
            .appendingPathComponent(LibraryLayout.documentManifestFile)
        if let m = try? await store.readJSON(DocumentManifest.self, at: manifestURL) {
            return summary(m, course: course, fileURL: pdf, manifestURL: manifestURL)
        }
        do {
            let m = try await makeManifest(forPDF: pdf, kind: kind, store: store)
            try await store.writeJSON(m, to: manifestURL)
            return summary(m, course: course, fileURL: pdf, manifestURL: manifestURL)
        } catch {
            AppLog.shared.error("Couldn't index \(pdf.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func makeManifest(forPDF pdf: URL, kind: DocumentKind, store: FileStore) async throws -> DocumentManifest {
        let now = Date()
        let title = LibraryLayout.stripExtension(pdf.lastPathComponent)
        switch kind {
        case .exampleSheet:
            // The questions PDF stays as the reference; answers start on one answer-sheet page.
            return DocumentManifest(
                id: UUID(), kind: .exampleSheet, title: title, sourcePDF: pdf.lastPathComponent,
                pages: [Page(background: .template(.answerSheet), question: 1)],
                sheet: ExampleSheetInfo(), createdAt: now, updatedAt: now
            )
        case .lectureNotes, .notebook:
            let sizes = try await store.pdfPageSizes(pdf)
            let relative = store.relativePath(of: pdf)
            let pages = sizes.enumerated().map { index, size in
                Page(size: size, background: .pdf(path: relative, pageIndex: index))
            }
            return DocumentManifest(
                id: UUID(), kind: .lectureNotes, title: title, sourcePDF: pdf.lastPathComponent,
                pages: pages, createdAt: now, updatedAt: now
            )
        }
    }

    private func summary(_ m: DocumentManifest, course: Course, fileURL: URL, manifestURL: URL) -> DocumentSummary {
        DocumentSummary(id: m.id, courseID: course.id, kind: m.kind, title: m.title, fileURL: fileURL,
                        manifestURL: manifestURL, pageCount: m.pages.count, updatedAt: m.updatedAt, sheet: m.sheet)
    }

    func loadManifest(for document: DocumentSummary) async throws -> DocumentManifest {
        guard let store = fileStore else { throw CocoaError(.fileNoSuchFile) }
        return try await store.readJSON(DocumentManifest.self, at: document.manifestURL)
    }

    func saveManifest(_ manifest: DocumentManifest, for document: DocumentSummary) async throws {
        guard let store = fileStore else { throw CocoaError(.fileNoSuchFile) }
        var m = manifest
        m.updatedAt = Date()
        try await store.writeJSON(m, to: document.manifestURL)
        if let course = self.manifest.course(document.courseID) { await rescan(course) }
    }

    /// Copies PDFs (from the document picker or a drop) into a course shelf and indexes them.
    func importPDFs(_ urls: [URL], into course: Course, kind: DocumentKind) async {
        guard let store = fileStore, let shelf = shelfURL(course, kind: kind == .notebook ? .lectureNotes : kind) else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let destination = try await store.importFile(from: url, into: shelf)
                AppLog.shared.info("Imported \(destination.lastPathComponent) into \(course.name)")
            } catch {
                AppLog.shared.error("Import of \(url.lastPathComponent) failed: \(error.localizedDescription)")
            }
        }
        await rescan(course)
    }

    @discardableResult
    func createNotebook(in course: Course, title: String, template: PageTemplate = .default) async -> DocumentSummary? {
        guard let store = fileStore, let shelf = shelfURL(course, kind: .notebook) else { return nil }
        let name = LibraryLayout.safeFileName(title.isEmpty ? "Untitled notebook" : title)
        var package = shelf.appendingPathComponent(LibraryLayout.manifestFolderName(kind: .notebook, fileName: name))
        var n = 2
        while await store.exists(package) {
            package = shelf.appendingPathComponent(LibraryLayout.manifestFolderName(kind: .notebook, fileName: "\(name) \(n)"))
            n += 1
        }
        let manifest = DocumentManifest.notebook(title: title.isEmpty ? "Untitled notebook" : title, template: template)
        let manifestURL = package.appendingPathComponent(LibraryLayout.documentManifestFile)
        do {
            try await store.ensureDirectory(package.appendingPathComponent(LibraryLayout.pagesDir))
            try await store.writeJSON(manifest, to: manifestURL)
            await rescan(course)
            return document(manifest.id)
        } catch {
            AppLog.shared.error("Creating notebook failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Recents (per install)

    func noteOpened(_ document: DocumentSummary, pageIndex: Int? = nil) {
        recents.removeAll { $0.documentID == document.id }
        recents.insert(RecentLocation(documentID: document.id, courseID: document.courseID, pageIndex: pageIndex, openedAt: Date()), at: 0)
        if recents.count > 20 { recents.removeLast(recents.count - 20) }
        if let data = try? JSONCoding.encode(recents, pretty: false) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let list = try? JSONCoding.decode([RecentLocation].self, from: data) else { return }
        recents = list
    }

    /// Recents that still resolve to a document.
    var recentDocuments: [DocumentSummary] {
        recents.compactMap { document($0.documentID) }
    }

    /// Example sheets with an upcoming supervision or hand-in date, soonest first.
    var upcomingSheets: [UpcomingSheet] {
        let today = self.today
        return allDocuments.compactMap { doc -> UpcomingSheet? in
            guard doc.kind == .exampleSheet, let sheet = doc.sheet else { return nil }
            let dates = [sheet.supervisionDate, sheet.handInDate].compactMap { $0 }.filter { $0 >= today }
            guard let soonest = dates.min() else { return nil }
            return UpcomingSheet(document: doc, date: soonest, isSupervision: soonest == sheet.supervisionDate)
        }
        .sorted { $0.date < $1.date }
    }
}

struct UpcomingSheet: Identifiable, Hashable {
    var id: UUID { document.id }
    let document: DocumentSummary
    let date: CalendarDate
    let isSupervision: Bool
}
