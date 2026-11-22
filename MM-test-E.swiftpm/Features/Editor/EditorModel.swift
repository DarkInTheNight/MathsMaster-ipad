import SwiftUI
import PencilKit
import PDFKit

/// State of one open document: its page list, the canvas, autosave, page edits and
/// example-sheet questions. One per open editor; the canvas controller lives as long as it does.
@MainActor
@Observable
final class EditorModel {
    enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }

    let document: DocumentSummary
    private(set) var phase: Phase = .loading
    private(set) var manifest: DocumentManifest
    private(set) var currentPageIndex = 0
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var hasUnsavedInk = false

    // Reference pane (example sheets: the questions; otherwise any PDF of the course).
    var showReference = false
    private(set) var referenceTitle: String?
    private(set) var referencePDF: PDFDocument?
    /// Bumped to make the reference pane scroll to `referenceTarget`.
    private(set) var referenceTarget: ReferenceTarget?

    // Example sheets
    private(set) var questionStarts: [QuestionDetector.Start] = []
    private(set) var questionsPDF: PDFDocument?

    private var fingerDrawing: Bool
    var drawWithFinger: Bool {
        get { fingerDrawing }
        set {
            fingerDrawing = newValue
            canvasController.drawWithFinger = newValue
            UserDefaults.standard.set(newValue, forKey: Self.drawWithFingerKey)
        }
    }

    @ObservationIgnored let canvasController = InkCanvasController()
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var sources: PDFSourceCache?
    /// What is on disk for each page, so autosave only writes pages that changed.
    @ObservationIgnored private var savedDrawings: [UUID: PKDrawing] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var manifestDirty = false

    private static let drawWithFingerKey = "editor.drawWithFinger"
    static let autosaveDelay: Duration = .seconds(2)

    struct ReferenceTarget: Equatable {
        var token = UUID()
        var pageIndex: Int
        var selectionRange: NSRange?
    }

    init(document: DocumentSummary, library: LibraryStore) {
        self.document = document
        self.library = library
        let now = Date()
        self.manifest = DocumentManifest(id: document.id, kind: document.kind, title: document.title, sourcePDF: nil,
                                         pages: [], createdAt: now, updatedAt: now)
        self.fingerDrawing = UserDefaults.standard.bool(forKey: Self.drawWithFingerKey)
        canvasController.drawWithFinger = fingerDrawing
        canvasController.delegate = self
    }

    var isExampleSheet: Bool { document.kind == .exampleSheet }
    var pageCount: Int { manifest.pages.count }
    var course: Course? { library.course(of: document) }
    var libraryFileStore: FileStore? { library.fileStore }

    // MARK: Loading

    func load() async {
        guard let store = library.fileStore else {
            phase = .failed("The library folder isn't open.")
            return
        }
        do {
            manifest = try await library.loadManifest(for: document)
        } catch {
            AppLog.shared.error("Opening \(document.title) failed: \(error)")
            phase = .failed("Couldn't open \(document.title): \(error.localizedDescription)")
            return
        }
        if manifest.pages.isEmpty {
            manifest.insertTemplatePage(at: 0)
            manifestDirty = true
        }

        let sources = PDFSourceCache(store: store, fallbackPDF: document.kind == .lectureNotes ? document.fileURL : nil)
        self.sources = sources
        await sources.load(paths: pdfPaths())

        // Ink: one file per page; only read the ones that exist.
        let existing = Set(((try? await store.listDirectory(document.pagesURL)) ?? []).map(\.lastPathComponent))
        var drawings: [UUID: PKDrawing] = [:]
        for page in manifest.pages {
            let name = LibraryLayout.pageInkFileName(pageID: page.id)
            guard existing.contains(name) else { continue }
            do {
                let data = try await store.readData(at: document.pagesURL.appendingPathComponent(name))
                drawings[page.id] = try PKDrawing(data: data)
            } catch {
                AppLog.shared.error("Couldn't read ink for a page of \(document.title): \(error.localizedDescription)")
            }
        }
        savedDrawings = drawings

        if isExampleSheet { await loadQuestions(store: store) }

        let startPage = manifest.lastPosition.flatMap { pos in manifest.pages.firstIndex { $0.id == pos.pageID } } ?? 0
        let zoom = manifest.lastPosition.map { CGFloat($0.zoom) } ?? 1
        currentPageIndex = startPage
        reloadCanvas(drawings: drawings, scrollTo: startPage, relativeZoom: zoom)
        if isExampleSheet, questionsPDF != nil { showReference = true }
        phase = .ready
        library.noteOpened(document, pageIndex: startPage)
        if manifestDirty { await saveManifest() }
    }

    private func pdfPaths() -> Set<String> {
        Set(manifest.pages.compactMap { page in
            if case .pdf(let path, _) = page.background { return path }
            return nil
        })
    }

    private func reloadCanvas(drawings: [UUID: PKDrawing], scrollTo page: Int?, relativeZoom: CGFloat? = nil) {
        guard let sources else { return }
        let pageSources = manifest.pages.map { sources.source(for: $0) }
        let dark = !pageSources.isEmpty && pageSources.allSatisfy(\.isDarkPaper)
        canvasController.load(pageIDs: manifest.pages.map(\.id), sources: pageSources, drawings: drawings,
                              darkPaper: dark, scrollToPage: page, relativeZoom: relativeZoom)
        refreshUndoState()
    }

    func backgroundSource(for page: Page) -> PageBackgroundSource? {
        sources?.source(for: page)
    }

    // MARK: Autosave (design plan §3.10, §7.4)

    private func scheduleSave() {
        hasUnsavedInk = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: EditorModel.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.saveInk()
        }
    }

    /// Writes the pages whose ink changed. Encoding happens here on the main actor;
    /// the coordinated, atomic writes happen on the FileStore actor.
    func saveInk() async {
        guard let store = library.fileStore, phase == .ready else { return }
        let current = canvasController.splitDrawing()
        var writes: [(UUID, Data)] = []
        for (id, drawing) in current where drawing != (savedDrawings[id] ?? PKDrawing()) {
            writes.append((id, drawing.dataRepresentation()))
            savedDrawings[id] = drawing
        }
        hasUnsavedInk = false
        for (id, data) in writes {
            let url = document.pagesURL.appendingPathComponent(LibraryLayout.pageInkFileName(pageID: id))
            do {
                try await store.writeData(data, to: url)
            } catch {
                savedDrawings[id] = nil
                hasUnsavedInk = true
                AppLog.shared.error("Saving ink in \(document.title) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Saves everything now (page change, backgrounding, closing).
    func flush(rememberPosition: Bool = false) async {
        saveTask?.cancel()
        guard phase == .ready else { return }
        await saveInk()
        if rememberPosition, manifest.pages.indices.contains(currentPageIndex) {
            let position = PagePosition(pageID: manifest.pages[currentPageIndex].id, zoom: Double(canvasController.relativeZoom))
            if manifest.lastPosition != position {
                manifest.lastPosition = position
                manifestDirty = true
            }
            library.noteOpened(document, pageIndex: currentPageIndex)
        }
        if manifestDirty { await saveManifest() }
    }

    private func saveManifest() async {
        manifestDirty = false
        do {
            try await library.saveManifest(manifest, for: document)
        } catch {
            manifestDirty = true
            AppLog.shared.error("Saving \(document.title) failed: \(error.localizedDescription)")
        }
    }

    // MARK: Undo

    func undo() { canvasController.undo(); refreshUndoState() }
    func redo() { canvasController.redo(); refreshUndoState() }

    private func refreshUndoState() {
        canUndo = canvasController.canUndo
        canRedo = canvasController.canRedo
    }

    // MARK: Pages (design plan §3.5)

    /// Applies a page-list edit: the ink is cut by page first, so it follows its page wherever it moves.
    private func editPages(scrollTo target: ((DocumentManifest) -> Int?)? = nil,
                           _ edit: (inout DocumentManifest, inout [UUID: PKDrawing]) -> Void) {
        var drawings = canvasController.splitDrawing()
        let before = Set(manifest.pages.map(\.id))
        let currentID = manifest.pages.indices.contains(currentPageIndex) ? manifest.pages[currentPageIndex].id : nil
        edit(&manifest, &drawings)
        let after = Set(manifest.pages.map(\.id))

        // Pages that are gone: their ink file goes to the library's .trash.
        for removed in before.subtracting(after) {
            savedDrawings[removed] = nil
            let url = document.pagesURL.appendingPathComponent(LibraryLayout.pageInkFileName(pageID: removed))
            if let store = library.fileStore {
                Task { if await store.exists(url) { try? await store.moveToTrash(url) } }
            }
        }
        let scrollIndex = target?(manifest) ?? currentID.flatMap { id in manifest.pages.firstIndex { $0.id == id } } ?? 0
        currentPageIndex = min(scrollIndex, max(0, manifest.pages.count - 1))
        reloadCanvas(drawings: drawings, scrollTo: currentPageIndex)
        manifestDirty = true
        Task {
            await sources?.load(paths: pdfPaths())
            await flush()
        }
    }

    func insertPage(at index: Int, template: PageTemplate? = nil) {
        editPages(scrollTo: { _ in index }) { m, _ in
            let question = m.kind == .exampleSheet ? m.effectiveQuestion(ofPageAt: max(0, index - 1)) : nil
            m.insertTemplatePage(at: index, template: template, question: question)
        }
    }

    func duplicatePage(at index: Int) {
        editPages(scrollTo: { _ in index + 1 }) { m, drawings in
            let original = m.pages.indices.contains(index) ? m.pages[index].id : nil
            if let copy = m.duplicatePage(at: index), let original {
                drawings[copy.id] = drawings[original]
            }
        }
    }

    func deletePages(at offsets: IndexSet) {
        editPages { m, _ in
            for i in offsets.sorted(by: >) { m.removePage(at: i) }
        }
    }

    func movePages(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        editPages { m, _ in m.movePages(fromOffsets: offsets, toOffset: destination) }
    }

    func setTemplate(_ template: PageTemplate, forPageAt index: Int?) {
        editPages { m, _ in
            m.setTemplate(template, at: index.map { [$0] } ?? Array(m.pages.indices))
        }
    }

    func setQuestion(_ question: Int?, forPageAt index: Int) {
        guard manifest.pages.indices.contains(index) else { return }
        manifest.pages[index].question = question
        manifestDirty = true
        Task { await flush() }
    }

    /// The template of the current page, if it's a template page (for menus).
    var currentTemplate: PageTemplate? {
        guard manifest.pages.indices.contains(currentPageIndex),
              case .template(let t) = manifest.pages[currentPageIndex].background else { return nil }
        return t
    }

    func goToPage(_ index: Int) {
        canvasController.scrollTo(pageIndex: index, animated: true)
    }

    /// Ink per page as it is now (for export, thumbnails).
    func currentDrawings() -> [UUID: PKDrawing] {
        canvasController.splitDrawing()
    }

    // MARK: Example sheets (design plan §3.7)

    private func loadQuestions(store: FileStore) async {
        do {
            let data = try await store.readData(at: document.fileURL)
            guard let pdf = PDFDocument(data: data) else { return }
            questionsPDF = pdf
            referencePDF = pdf
            referenceTitle = "Questions"
            let texts = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
            questionStarts = QuestionDetector.detect(pageTexts: texts)
            var sheet = manifest.sheet ?? ExampleSheetInfo()
            let before = sheet
            sheet.ensureQuestions(count: max(questionStarts.count, sheet.questions.count == 0 ? 1 : 0))
            if sheet != before || manifest.sheet == nil {
                manifest.sheet = sheet
                manifestDirty = true
            }
        } catch {
            AppLog.shared.error("Couldn't read the questions of \(document.title): \(error.localizedDescription)")
        }
    }

    var questions: [SheetQuestion] { manifest.sheet?.questions ?? [] }

    /// The question the page on screen answers.
    var currentQuestion: Int? { manifest.effectiveQuestion(ofPageAt: currentPageIndex) }

    func status(of question: Int) -> QuestionStatus {
        manifest.sheet?.status(of: question) ?? .notStarted
    }

    func setStatus(_ status: QuestionStatus, for question: Int) {
        var sheet = manifest.sheet ?? ExampleSheetInfo()
        sheet.setStatus(status, for: question)
        manifest.sheet = sheet
        manifestDirty = true
        Task { await flush() }
    }

    /// Tapping Q4: the questions scroll to Q4 and the answers to the first page tagged Q4,
    /// which is created if needed.
    func goToQuestion(_ number: Int) {
        if let start = questionStarts.first(where: { $0.number == number }) {
            referenceTarget = ReferenceTarget(pageIndex: start.page, selectionRange: NSRange(location: start.offset, length: start.length))
            if referencePDF !== questionsPDF, let questionsPDF {
                referencePDF = questionsPDF
                referenceTitle = "Questions"
            }
        }
        if let index = manifest.firstPageIndex(forQuestion: number) {
            currentPageIndex = index
            goToPage(index)
        } else {
            editPages(scrollTo: { m in m.firstPageIndex(forQuestion: number) }) { m, _ in
                m.addAnswerPage(forQuestion: number)
            }
        }
    }

    /// Adds the next question by hand (when detection missed some).
    func addQuestion() {
        var sheet = manifest.sheet ?? ExampleSheetInfo()
        let next = (sheet.questions.map(\.number).max() ?? 0) + 1
        sheet.ensureQuestions(count: next)
        manifest.sheet = sheet
        manifestDirty = true
        goToQuestion(next)
    }

    // MARK: Reference pane

    /// PDFs in the same course that can be shown beside the canvas.
    var referenceCandidates: [DocumentSummary] {
        guard let course else { return [] }
        return (library.documents(in: course, kind: .lectureNotes) + library.documents(in: course, kind: .exampleSheet))
            .filter { $0.id != document.id || isExampleSheet }
    }

    func openReference(_ candidate: DocumentSummary) async {
        if isExampleSheet, candidate.id == document.id, let questionsPDF {
            referencePDF = questionsPDF
            referenceTitle = "Questions"
            showReference = true
            return
        }
        guard let store = library.fileStore else { return }
        do {
            let data = try await store.readData(at: candidate.fileURL)
            referencePDF = PDFDocument(data: data)
            referenceTitle = candidate.title
            showReference = referencePDF != nil
        } catch {
            AppLog.shared.error("Couldn't open \(candidate.title) as a reference: \(error.localizedDescription)")
        }
    }
}

extension EditorModel: InkCanvasControllerDelegate {
    func inkCanvasDrawingDidChange() {
        refreshUndoState()
        scheduleSave()
    }

    func inkCanvasCurrentPageDidChange(_ index: Int) {
        currentPageIndex = index
    }
}
