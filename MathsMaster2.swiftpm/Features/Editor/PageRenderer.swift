import UIKit
import PDFKit

/// What sits under the ink on one page, resolved to something drawable.
/// Immutable, so the tiled layers can draw it on background threads.
final class PageBackgroundSource: @unchecked Sendable {
    enum Content {
        case pdf(CGPDFPage)
        case template(PageTemplate)
        /// The PDF is missing or still downloading from iCloud.
        case missing
    }

    let content: Content
    let size: CGSize

    init(content: Content, size: CGSize) {
        self.content = content
        self.size = size
    }

    var isDarkPaper: Bool {
        if case .template(let t) = content { return t.paper == .dark }
        return false
    }
}

/// Draws page backgrounds: PDF pages as vectors, templates as lines the app draws itself
/// (so they can be left out when printing, design plan §3.5, §3.8).
/// The context must have a top-left origin with the page at (0, 0) in points.
enum PageRenderer {
    struct Options {
        /// Draw dots, squares and rules (export can turn this off).
        var templateLines = true
        /// Exports always use white paper, whatever is shown on screen.
        var forPrint = false
    }

    static let pointsPerMM: CGFloat = 72 / 25.4

    static func draw(_ source: PageBackgroundSource, in ctx: CGContext, options: Options = Options(), clip: CGRect? = nil) {
        let rect = CGRect(origin: .zero, size: source.size)
        switch source.content {
        case .pdf(let page):
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(rect)
            drawPDFPage(page, in: ctx, size: source.size)
        case .template(let template):
            let paper = paperColour(template.paper, forPrint: options.forPrint)
            ctx.setFillColor(paper.cgColor)
            ctx.fill(rect)
            if options.templateLines {
                drawTemplate(template, in: ctx, size: source.size, forPrint: options.forPrint, clip: clip ?? rect)
            }
        case .missing:
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(rect)
        }
    }

    static func drawPDFPage(_ page: CGPDFPage, in ctx: CGContext, size: CGSize) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        ctx.interpolationQuality = .high
        ctx.setRenderingIntent(.defaultIntent)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }

    static func paperColour(_ paper: PaperColour, forPrint: Bool) -> UIColor {
        if forPrint { return .white }
        switch paper {
        case .white: return .white
        case .cream: return UIColor(hex: 0xFBF6EA)
        case .dark: return UIColor(hex: 0x1E1F22)
        }
    }

    private static func lineColour(_ paper: PaperColour, forPrint: Bool) -> UIColor {
        if forPrint { return UIColor(white: 0.72, alpha: 1) }
        switch paper {
        case .white, .cream: return UIColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 0.55)
        case .dark: return UIColor(white: 1, alpha: 0.22)
        }
    }

    private static func drawTemplate(_ template: PageTemplate, in ctx: CGContext, size: CGSize, forPrint: Bool, clip: CGRect) {
        let colour = lineColour(template.paper, forPrint: forPrint)
        let step = max(2, CGFloat(template.spacingMM)) * pointsPerMM
        let hairline: CGFloat = 0.5
        ctx.saveGState()
        ctx.setStrokeColor(colour.cgColor)
        ctx.setFillColor(colour.cgColor)
        ctx.setLineWidth(hairline)

        func columns(in area: CGRect) -> StrideTo<CGFloat> {
            let first = (max(area.minX, clip.minX) / step).rounded(.up) * step
            return stride(from: max(first, step), to: min(area.maxX, clip.maxX), by: step)
        }
        func rows(in area: CGRect) -> StrideTo<CGFloat> {
            let first = (max(area.minY, clip.minY) / step).rounded(.up) * step
            return stride(from: max(first, step), to: min(area.maxY, clip.maxY), by: step)
        }

        let page = CGRect(origin: .zero, size: size)
        switch template.kind {
        case .blank:
            break
        case .dotGrid:
            let r: CGFloat = 0.75
            for y in rows(in: page) {
                for x in columns(in: page) {
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
        case .squared:
            for x in columns(in: page) { ctx.move(to: CGPoint(x: x, y: max(0, clip.minY))); ctx.addLine(to: CGPoint(x: x, y: min(size.height, clip.maxY))) }
            for y in rows(in: page) { ctx.move(to: CGPoint(x: max(0, clip.minX), y: y)); ctx.addLine(to: CGPoint(x: min(size.width, clip.maxX), y: y)) }
            ctx.strokePath()
        case .ruled:
            let top = 25 * pointsPerMM
            let area = CGRect(x: 0, y: top, width: size.width, height: size.height - top)
            for y in rows(in: area) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)) }
            ctx.strokePath()
            // Margin line
            let marginX = 25 * pointsPerMM
            ctx.setStrokeColor(UIColor(red: 0.85, green: 0.35, blue: 0.35, alpha: forPrint ? 0.6 : 0.45).cgColor)
            ctx.move(to: CGPoint(x: marginX, y: 0)); ctx.addLine(to: CGPoint(x: marginX, y: size.height))
            ctx.strokePath()
        case .answerSheet:
            // Header band with fields, 5 mm squares, and a 30 mm right margin for the supervisor.
            let header = 22 * pointsPerMM
            let margin = 30 * pointsPerMM
            let grid = CGRect(x: 0, y: header, width: size.width - margin, height: size.height - header)
            for x in columns(in: grid) { ctx.move(to: CGPoint(x: x, y: header)); ctx.addLine(to: CGPoint(x: x, y: size.height)) }
            for y in rows(in: grid) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: grid.maxX, y: y)) }
            ctx.strokePath()
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: grid.maxX, y: header)); ctx.addLine(to: CGPoint(x: grid.maxX, y: size.height))
            ctx.move(to: CGPoint(x: 0, y: header)); ctx.addLine(to: CGPoint(x: size.width, y: header))
            ctx.strokePath()
            if clip.minY < header {
                drawHeaderFields(in: ctx, width: size.width, height: header, colour: colour)
            }
        }
        ctx.restoreGState()
    }

    private static func drawHeaderFields(in ctx: CGContext, width: CGFloat, height: CGFloat, colour: UIColor) {
        let labels = ["Course", "Sheet", "Q"]
        let widths: [CGFloat] = [0.5, 0.3, 0.2]
        let inset: CGFloat = 14
        var x = inset
        let usable = width - 2 * inset
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: colour.withAlphaComponent(1),
        ]
        UIGraphicsPushContext(ctx)
        for (label, fraction) in zip(labels, widths) {
            let w = usable * fraction
            (label.uppercased() as NSString).draw(at: CGPoint(x: x, y: height * 0.22), withAttributes: attributes)
            ctx.move(to: CGPoint(x: x, y: height * 0.78))
            ctx.addLine(to: CGPoint(x: x + w - 10, y: height * 0.78))
            x += w
        }
        ctx.strokePath()
        UIGraphicsPopContext()
    }
}

/// Opens the PDFs a document's pages refer to (coordinated reads through `FileStore`) and
/// resolves each page's background.
@MainActor
final class PDFSourceCache {
    private var documents: [String: CGPDFDocument] = [:]
    private var failed: Set<String> = []
    private let store: FileStore
    /// Lecture notes: if a page's PDF path no longer resolves (the course or file was renamed in
    /// Files), fall back to the document's own PDF.
    private let fallbackPDF: URL?

    init(store: FileStore, fallbackPDF: URL? = nil) {
        self.store = store
        self.fallbackPDF = fallbackPDF
    }

    func load(paths: Set<String>) async {
        for path in paths where documents[path] == nil && !failed.contains(path) {
            if let doc = await open(store.url(path)) {
                documents[path] = doc
            } else if let fallbackPDF, let doc = await open(fallbackPDF) {
                AppLog.shared.info("\(path) not found; using \(fallbackPDF.lastPathComponent)")
                documents[path] = doc
            } else {
                failed.insert(path)
            }
        }
    }

    private func open(_ url: URL) async -> CGPDFDocument? {
        do {
            let data = try await store.readData(at: url)
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGPDFDocument(provider)
        } catch {
            AppLog.shared.error("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    func source(for page: Page) -> PageBackgroundSource {
        let size = CGSize(width: page.size.width, height: page.size.height)
        switch page.background {
        case .template(let template):
            return PageBackgroundSource(content: .template(template), size: size)
        case .pdf(let path, let index):
            // CGPDFDocument pages are 1-based.
            if let cgPage = documents[path]?.page(at: index + 1) {
                return PageBackgroundSource(content: .pdf(cgPage), size: size)
            }
            return PageBackgroundSource(content: .missing, size: size)
        }
    }
}
