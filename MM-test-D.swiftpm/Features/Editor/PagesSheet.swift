import SwiftUI
import PencilKit

/// Page operations (design plan §3.5): go to, insert, duplicate, move, delete, change template,
/// and for example sheets, which question a page answers.
struct PagesSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var drawings: [UUID: PKDrawing] = [:]
    @State private var thumbnails: [UUID: UIImage] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.manifest.pages.enumerated()), id: \.element.id) { index, page in
                    row(index: index, page: page)
                }
                .onMove { offsets, destination in
                    model.movePages(fromOffsets: offsets, toOffset: destination)
                    refreshDrawings()
                }
                .onDelete { offsets in
                    guard model.pageCount - offsets.count >= 1 else { return }
                    model.deletePages(at: offsets)
                    refreshDrawings()
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        ForEach(TemplateKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) {
                                model.insertPage(at: model.pageCount, template: TemplateMenu.template(kind, paper: model.currentTemplate?.paper ?? .white))
                                refreshDrawings()
                            }
                        }
                    } label: {
                        Label("Add page at end", systemImage: "plus")
                    } primaryAction: {
                        model.insertPage(at: model.pageCount)
                        refreshDrawings()
                    }
                }
            }
            .onAppear { refreshDrawings() }
        }
    }

    private func refreshDrawings() {
        drawings = model.currentDrawings()
        thumbnails = [:]
    }

    private func row(index: Int, page: Page) -> some View {
        Button {
            model.goToPage(index)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                thumbnail(page)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Page \(index + 1)").font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle(page)).font(.subheadline).foregroundStyle(Theme.ink2)
                }
                Spacer()
                if index == model.currentPageIndex {
                    Image(systemName: "eye").foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { pageMenu(index: index, page: page) }
    }

    @ViewBuilder
    private func pageMenu(index: Int, page: Page) -> some View {
        Button("Insert page before", systemImage: "arrow.up.doc") {
            model.insertPage(at: index)
            refreshDrawings()
        }
        Button("Insert page after", systemImage: "arrow.down.doc") {
            model.insertPage(at: index + 1)
            refreshDrawings()
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            model.duplicatePage(at: index)
            refreshDrawings()
        }
        if case .template(let template) = page.background {
            TemplateMenu(title: "Change paper", current: template) { t in
                model.setTemplate(t, forPageAt: index)
                refreshDrawings()
            }
        }
        if model.isExampleSheet {
            Menu("Answers question…") {
                ForEach(model.questions) { q in
                    Button("Q\(q.number)") { model.setQuestion(q.number, forPageAt: index) }
                }
            }
        }
        if model.pageCount > 1 {
            Button("Delete page", systemImage: "trash", role: .destructive) {
                model.deletePages(at: IndexSet(integer: index))
                refreshDrawings()
            }
        }
    }

    private func subtitle(_ page: Page) -> String {
        var parts: [String] = []
        if let q = page.question { parts.append("Q\(q)") }
        switch page.background {
        case .pdf(_, let pageIndex): parts.append("PDF page \(pageIndex + 1)")
        case .template(let t): parts.append(t.kind.displayName)
        }
        if let ink = drawings[page.id], !ink.strokes.isEmpty { parts.append("ink") }
        return parts.joined(separator: " · ")
    }

    private func thumbnail(_ page: Page) -> some View {
        let width: CGFloat = 64
        let aspect = page.size.height / max(1, page.size.width)
        return Group {
            if let image = thumbnails[page.id] {
                Image(uiImage: image).resizable()
            } else {
                Rectangle().fill(Color.white)
                    .task(id: page.id) {
                        guard let source = model.backgroundSource(for: page) else { return }
                        thumbnails[page.id] = PDFExporter.thumbnail(source: source, drawing: drawings[page.id] ?? PKDrawing(),
                                                                    width: width, displayScale: displayScale)
                    }
            }
        }
        .frame(width: width, height: width * aspect)
        .overlay(Rectangle().strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
