import SwiftUI
import PDFKit

// WORKSTREAM B owns everything in Features/Editor.
//
// Contract with the rest of the app:
// - Entry point: `DocumentEditorView(document: DocumentSummary)`, pushed full screen by `AppRoute.document`.
// - Page list via `LibraryStore.loadManifest(for:)` / `saveManifest(_:for:)`; ink is one PKDrawing per
//   page at `document.pagesURL/<pageID>.drawing`, read and written through `library.fileStore`.
// - The original PDFs are never modified.
//
// Pieces: EditorModel (state, autosave, page edits) · InkCanvasController (the one PKCanvasView over
// a tiled page stack) · PageRenderer (templates, PDF pages) · PDFExporter (export, print) ·
// EditorPanels (reference pane, question bar) · PagesSheet · ExportSheet.

struct DocumentEditorView: View {
    @Environment(LibraryStore.self) private var library
    let document: DocumentSummary
    @State private var model: EditorModel?

    var body: some View {
        Group {
            if let model {
                EditorScreen(model: model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let m = EditorModel(document: document, library: library)
            model = m
            await m.load()
        }
    }
}

private struct EditorScreen: View {
    @Bindable var model: EditorModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPages = false
    @State private var showingExport = false
    @State private var exportHandIn = false
    @State private var referenceFraction: CGFloat = 0.4

    var body: some View {
        content
            .toolbar { toolbar }
            .sheet(isPresented: $showingPages, onDismiss: { model.canvasController.activateToolPicker() }) {
                PagesSheet(model: model)
            }
            .sheet(isPresented: $showingExport, onDismiss: { model.canvasController.activateToolPicker() }) {
                ExportSheet(model: model, handIn: exportHandIn)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { flushInBackground() }
            }
            .onDisappear {
                model.canvasController.hideToolPicker()
                flushInBackground(rememberPosition: true)
            }
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Opening…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Couldn't open", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            VStack(spacing: 0) {
                if model.isExampleSheet {
                    QuestionBar(model: model)
                    Divider()
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if model.showReference, let pdf = model.referencePDF {
                            ReferencePane(model: model, pdf: pdf)
                                .frame(width: max(240, geo.size.width * referenceFraction))
                            divider(totalWidth: geo.size.width)
                        }
                        InkCanvasView(controller: model.canvasController)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 6)
            .overlay(Capsule().fill(Theme.ink2.opacity(0.5)).frame(width: 3, height: 36))
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        guard totalWidth > 0 else { return }
                        let fraction = referenceFraction + value.translation.width / totalWidth
                        referenceFraction = min(0.6, max(0.25, fraction))
                    }
            )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(model.manifest.title).font(.headline).lineLimit(1)
                Text(pageLine).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            referenceMenu
            Button { showingPages = true } label: { Label("Pages", systemImage: "square.grid.2x2") }
            shareMenu
            moreMenu
        }
    }

    private var pageLine: String {
        var line = "p. \(model.currentPageIndex + 1) / \(model.pageCount)"
        if model.isExampleSheet, let q = model.currentQuestion { line = "Q\(q) · " + line }
        return line
    }

    private var referenceMenu: some View {
        Menu {
            if model.showReference {
                Button("Hide reference pane", systemImage: "sidebar.left") { model.showReference = false }
            }
            ForEach(model.referenceCandidates) { candidate in
                Button(candidate.id == model.document.id ? "Questions" : candidate.title) {
                    Task { await model.openReference(candidate) }
                }
            }
        } label: {
            Label("Reference pane", systemImage: model.showReference ? "rectangle.lefthalf.inset.filled" : "rectangle.split.2x1")
        } primaryAction: {
            if model.showReference || model.referencePDF != nil {
                model.showReference.toggle()
            } else if let first = model.referenceCandidates.first {
                Task { await model.openReference(first) }
            }
        }
    }

    private var shareMenu: some View {
        Menu {
            Button("Export PDF…", systemImage: "square.and.arrow.up") {
                exportHandIn = false
                showingExport = true
            }
            if model.isExampleSheet {
                Button("Hand in…", systemImage: "tray.and.arrow.up") {
                    exportHandIn = true
                    showingExport = true
                }
            }
            Button("Print…", systemImage: "printer") {
                var options = ExportOptions()
                options.handIn = model.isExampleSheet
                options.templateLines = model.document.kind != .notebook
                model.printPDF(options: options)
            }
        } label: {
            Label("Share or print", systemImage: "square.and.arrow.up")
        }
    }

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $model.drawWithFinger) {
                Label("Draw with finger", systemImage: "hand.point.up.left")
            }
            Button("Insert page after this one", systemImage: "doc.badge.plus") {
                model.insertPage(at: model.currentPageIndex + 1)
            }
            TemplateMenu(title: "Paper for all pages", current: model.currentTemplate) { template in
                model.setTemplate(template, forPageAt: nil)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    /// Saves with a background-task grace period, so closing the app mid-stroke loses nothing.
    private func flushInBackground(rememberPosition: Bool = false) {
        let task = InkSaveBackgroundTask(name: "Save ink")
        Task {
            await model.flush(rememberPosition: rememberPosition)
            task.end()
        }
    }
}

/// `beginBackgroundTask` wrapper: about 30 s to finish saving after the app goes to the background.
@MainActor
final class InkSaveBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Wraps the canvas controller once; SwiftUI updates never touch the canvas (design plan §3.10).
struct InkCanvasView: UIViewControllerRepresentable {
    let controller: InkCanvasController

    func makeUIViewController(context: Context) -> InkCanvasController { controller }
    func updateUIViewController(_ controller: InkCanvasController, context: Context) {}
}

/// Template kinds × paper colours, as a menu.
struct TemplateMenu: View {
    let title: String
    let current: PageTemplate?
    let choose: (PageTemplate) -> Void

    var body: some View {
        Menu(title) {
            ForEach(TemplateKind.allCases, id: \.self) { kind in
                Button {
                    choose(Self.template(kind, paper: current?.paper ?? .white))
                } label: {
                    if current?.kind == kind { Label(kind.displayName, systemImage: "checkmark") } else { Text(kind.displayName) }
                }
            }
            Divider()
            ForEach(PaperColour.allCases, id: \.self) { paper in
                Button {
                    var t = current ?? .default
                    t.paper = paper
                    choose(t)
                } label: {
                    if current?.paper == paper { Label(paper.displayName, systemImage: "checkmark") } else { Text(paper.displayName) }
                }
            }
        }
    }

    static func template(_ kind: TemplateKind, paper: PaperColour) -> PageTemplate {
        switch kind {
        case .ruled: return PageTemplate(kind: .ruled, spacingMM: 7, paper: paper)
        default: return PageTemplate(kind: kind, spacingMM: 5, paper: paper)
        }
    }
}

extension PaperColour {
    var displayName: String {
        switch self {
        case .white: return "White paper"
        case .cream: return "Cream paper"
        case .dark: return "Dark paper"
        }
    }
}

/// Read-only PDF view (kept from the scaffold; used by other screens).
struct ReadOnlyPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(hex: 0xE9E6E0)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
