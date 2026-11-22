import UIKit
import PencilKit

/// UserDefaults key (per install) for the name printed on hand-ins.
let editorHandInNameKey = "editor.handInName"

/// Export, print and hand-in for the open document (design plan §3.7, §3.8).
extension EditorModel {

    struct ExportResult {
        var data: Data
        var fileName: String
        /// A copy in the app's temporary folder, for the share sheet.
        var shareURL: URL
        /// Where it was saved in the library (`Exports/`), if that worked.
        var libraryURL: URL?
    }

    func pageIndices(for options: ExportOptions) -> [Int] {
        var indices: [Int]
        switch options.scope {
        case .all:
            indices = Array(manifest.pages.indices)
        case .current:
            indices = manifest.pages.indices.contains(currentPageIndex) ? [currentPageIndex] : []
        case .currentQuestion:
            let q = currentQuestion
            indices = manifest.pages.indices.filter { manifest.effectiveQuestion(ofPageAt: $0) == q }
        }
        if options.handIn {
            let order = manifest.handInPageOrder()
            let wanted = Set(indices)
            indices = order.filter { wanted.contains($0) }
        }
        return indices
    }

    func exportFileName(options: ExportOptions) -> String {
        let courseName = course?.name ?? ""
        if options.handIn {
            let name = (UserDefaults.standard.string(forKey: editorHandInNameKey) ?? "").trimmingCharacters(in: .whitespaces)
            let surname = name.split(separator: " ").last.map(String.init) ?? ""
            let core = [courseName, manifest.title].filter { !$0.isEmpty }.joined(separator: " ")
            return LibraryLayout.safeFileName(surname.isEmpty ? core : "\(surname), \(core)") + ".pdf"
        }
        let base = manifest.title.localizedCaseInsensitiveContains(courseName) || courseName.isEmpty
            ? manifest.title : "\(courseName) – \(manifest.title)"
        return LibraryLayout.safeFileName(base) + ".pdf"
    }

    func renderPDF(options: ExportOptions) -> Data {
        let drawings = currentDrawings()
        let indices = pageIndices(for: options)
        let name = (UserDefaults.standard.string(forKey: editorHandInNameKey) ?? "").trimmingCharacters(in: .whitespaces)
        let items: [PDFExporter.Item] = indices.enumerated().compactMap { position, index in
            let page = manifest.pages[index]
            guard let source = backgroundSource(for: page) else { return nil }
            var parts: [String] = []
            if options.handIn, !name.isEmpty { parts.append(name) }
            if let course { parts.append(course.name) }
            parts.append(manifest.title)
            if isExampleSheet, let q = manifest.effectiveQuestion(ofPageAt: index) { parts.append("Q\(q)") }
            parts.append("\(position + 1) / \(indices.count)")
            return PDFExporter.Item(source: source, drawing: drawings[page.id] ?? PKDrawing(), footer: parts.joined(separator: "  ·  "))
        }
        return PDFExporter.render(items, title: manifest.title, options: options)
    }

    /// Renders, saves to `Exports/` in the library (so it also reaches the PC through iCloud)
    /// and to a temporary file for sharing.
    func export(options: ExportOptions) async -> ExportResult? {
        let data = renderPDF(options: options)
        let fileName = exportFileName(options: options)
        let shareURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: shareURL, options: .atomic)
        } catch {
            AppLog.shared.error("Couldn't write the export: \(error.localizedDescription)")
            return nil
        }
        var libraryURL: URL?
        if let store = libraryFileStore {
            let url = store.url(LibraryLayout.exportsDir).appendingPathComponent(fileName)
            do {
                try await store.writeData(data, to: url)
                libraryURL = url
            } catch {
                AppLog.shared.error("Couldn't save \(fileName) to Exports: \(error.localizedDescription)")
            }
        }
        AppLog.shared.info("Exported \(fileName) (\(data.count / 1024) KB)")
        return ExportResult(data: data, fileName: fileName, shareURL: shareURL, libraryURL: libraryURL)
    }

    func printPDF(options: ExportOptions) {
        let data = renderPDF(options: options)
        PrintService.print(data, jobName: LibraryLayout.stripExtension(exportFileName(options: options)))
    }
}
