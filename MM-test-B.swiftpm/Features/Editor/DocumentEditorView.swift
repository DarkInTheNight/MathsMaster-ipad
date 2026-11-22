import SwiftUI
import PDFKit

// WORKSTREAM B owns everything in Features/Editor.
//
// Contract with the rest of the app:
// - Entry point: `DocumentEditorView(document: DocumentSummary)`, pushed full screen by `AppRoute.document`.
// - Load/save the page list with `LibraryStore.loadManifest(for:)` / `saveManifest(_:for:)`.
// - Page ink: one PKDrawing per page at `document.pagesURL/<pageID>.drawing`
//   (`LibraryLayout.pageInkFileName(pageID:)`), read and written through `library.fileStore`.
// - PDF pages: `PageBackground.pdf(path:pageIndex:)`, path relative to the library root
//   (`library.fileStore.url(path)`); the original PDF is never modified.
// - Call `library.noteOpened(document, pageIndex:)` so Today → Continue works.
//
// This placeholder shows PDFs read-only so the scaffold is usable today.

struct DocumentEditorView: View {
    @Environment(LibraryStore.self) private var library
    let document: DocumentSummary

    var body: some View {
        Group {
            switch document.kind {
            case .lectureNotes, .exampleSheet:
                ReadOnlyPDFView(url: document.fileURL)
                    .ignoresSafeArea(edges: .bottom)
            case .notebook:
                ContentUnavailableView(
                    "Notebook",
                    systemImage: "pencil.and.scribble",
                    description: Text("Writing with the Pencil arrives with the editor.")
                )
            }
        }
        .background(Theme.background)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { library.noteOpened(document) }
    }
}

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
