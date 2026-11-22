import UIKit
import PencilKit

/// Export and print options (design plan §3.8). One sheet serves both.
struct ExportOptions: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case all, current, currentQuestion
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All pages"
            case .current: return "Current page"
            case .currentQuestion: return "Current question"
            }
        }
    }

    var scope: Scope = .all
    var templateLines = false
    var highlighter = true
    var allBlack = false
    var footer = true
    /// Example sheets: answers in question order, hand-in file name.
    var handIn = false
}

/// Flattens pages to a PDF: the background as vectors (the original PDF page or the template),
/// the ink on top rasterised at 300 dpi, which is crisp on paper.
@MainActor
enum PDFExporter {
    struct Item {
        var source: PageBackgroundSource
        var drawing: PKDrawing
        var footer: String?
    }

    static let inkDPI: CGFloat = 300

    static func render(_ items: [Item], title: String, options: ExportOptions) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "MathsMaster",
        ]
        let first = items.first.map { CGRect(origin: .zero, size: $0.source.size) } ?? CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
        let renderer = UIGraphicsPDFRenderer(bounds: first, format: format)
        return renderer.pdfData { context in
            for item in items {
                autoreleasepool {
                    let rect = CGRect(origin: .zero, size: item.source.size)
                    context.beginPage(withBounds: rect, pageInfo: [:])
                    let cg = context.cgContext
                    PageRenderer.draw(item.source, in: cg,
                                      options: PageRenderer.Options(templateLines: options.templateLines, forPrint: true))
                    drawInk(prepare(item.drawing, options: options), in: rect)
                    if let footer = item.footer, options.footer {
                        drawFooter(footer, in: rect)
                    }
                }
            }
        }
    }

    /// Applies "include highlighter" and "all black".
    static func prepare(_ drawing: PKDrawing, options: ExportOptions) -> PKDrawing {
        guard !options.highlighter || options.allBlack else { return drawing }
        var strokes: [PKStroke] = []
        for stroke in drawing.strokes {
            let isHighlighter = stroke.ink.inkType == .marker
            if isHighlighter && !options.highlighter { continue }
            if options.allBlack && !isHighlighter {
                strokes.append(PKStroke(ink: PKInk(stroke.ink.inkType, color: .black), path: stroke.path,
                                        transform: stroke.transform, mask: stroke.mask))
            } else {
                strokes.append(stroke)
            }
        }
        return PKDrawing(strokes: strokes)
    }

    /// Draws ink as it looks on white paper (light appearance, so black stays black even if
    /// the app or the page is dark).
    static func drawInk(_ drawing: PKDrawing, in rect: CGRect, scale: CGFloat = inkDPI / 72) {
        let bounds = drawing.bounds.intersection(rect)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        image?.draw(in: bounds)
    }

    private static func drawFooter(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - 18), withAttributes: attributes)
    }

    /// A small page image (background + ink) for the Pages list.
    static func thumbnail(source: PageBackgroundSource, drawing: PKDrawing, width: CGFloat, displayScale: CGFloat) -> UIImage {
        let scale = width / max(1, source.size.width)
        let size = CGSize(width: width, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            PageRenderer.draw(source, in: cg)
            drawInk(drawing, in: CGRect(origin: .zero, size: source.size), scale: scale * displayScale)
        }
    }
}

/// AirPrint (design plan §3.8).
@MainActor
enum PrintService {
    static func print(_ data: Data, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true) { _, completed, error in
            let message = error.map { "Printing failed: \($0.localizedDescription)" } ?? (completed ? "Printed \(jobName)" : nil)
            if let message {
                Task { @MainActor in AppLog.shared.info(message) }
            }
        }
    }
}
