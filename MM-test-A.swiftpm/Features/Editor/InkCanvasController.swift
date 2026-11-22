import UIKit
import PencilKit

@MainActor
protocol InkCanvasControllerDelegate: AnyObject {
    /// A stroke finished, was erased, moved, undone… (not called while loading).
    func inkCanvasDrawingDidChange()
    func inkCanvasCurrentPageDidChange(_ index: Int)
}

/// The page engine's view (design plan §3.1, plan B): ONE `PKCanvasView` for the whole document,
/// with the pages laid out as a vertical stack underneath it.
///
/// Why one canvas: PencilKit renders ink natively at the canvas's zoom scale, so ink stays sharp at
/// any zoom; there is one undo stack across pages; the lasso can move ink between pages; and
/// fingers scroll and pinch the same scroll view that the Pencil draws on, exactly like Notes.
/// Page backgrounds are tiled layers in a container that is scaled with the zoom, so PDF text
/// and template lines are re-rendered sharp too. Ink is stored per page in page coordinates:
/// `splitDrawing()` cuts the canvas drawing by page, `load` puts the pages back together.
///
/// The controller is created once per open document and wrapped once by SwiftUI, so the canvas
/// is never recreated by a view update (§3.10).
final class InkCanvasController: UIViewController, PKCanvasViewDelegate, PKToolPickerObserver, UIGestureRecognizerDelegate {
    weak var delegate: InkCanvasControllerDelegate?

    let canvas = PKCanvasView()
    let toolPicker = PKToolPicker()
    private let pagesContainer = UIView()

    private(set) var layout = PageStackLayout(sizes: [])
    private var pageIDs: [UUID] = []
    private var sources: [PageBackgroundSource] = []
    private var pageViews: [UUID: TiledPageView] = [:]
    private(set) var currentPageIndex = 0

    private var isLoading = false
    private var lastLayoutWidth: CGFloat = 0
    /// Zoom relative to "fit width" (1 = page width fills the view).
    private var pendingRelativeZoom: CGFloat = 1
    private var pendingScrollPage: Int?
    private var bottomObscured: CGFloat = 0
    private var savedNavGestureTouchTypes: [(UIGestureRecognizer, [NSNumber])] = []

    var drawWithFinger = false {
        didSet { canvas.drawingPolicy = drawWithFinger ? .anyInput : .pencilOnly }
    }

    // MARK: View

    override func loadView() {
        let root = UIView()
        root.backgroundColor = UIColor(hex: 0xE9E6E0)
        view = root

        canvas.frame = root.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.delegate = self
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = drawWithFinger ? .anyInput : .pencilOnly
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.bouncesZoom = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
        root.addSubview(canvas)

        pagesContainer.isUserInteractionEnabled = false
        pagesContainer.layer.anchorPoint = .zero
        pagesContainer.layer.position = .zero
        canvas.insertSubview(pagesContainer, at: 0)

        toolPicker.stateAutosaveName = "MathsMaster.editor.tools"
        toolPicker.addObserver(canvas)
        toolPicker.addObserver(self)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap))
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        undoTap.delegate = self
        canvas.addGestureRecognizer(undoTap)
        let redoTap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        redoTap.numberOfTouchesRequired = 3
        redoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        redoTap.delegate = self
        canvas.addGestureRecognizer(redoTap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateToolPicker()
        protectPencilFromNavigationGestures(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        protectPencilFromNavigationGestures(false)
    }

    /// Shows the system tool picker for the canvas (it follows the first responder).
    func activateToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvas)
        if canvas.window != nil, !canvas.isFirstResponder {
            canvas.becomeFirstResponder()
        }
    }

    func hideToolPicker() {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }

    /// The back-swipe gestures of the navigation stack must not steal Pencil strokes that start
    /// near the edge (§3.10): while the editor is on screen they only respond to fingers.
    private func protectPencilFromNavigationGestures(_ protect: Bool) {
        if protect {
            guard savedNavGestureTouchTypes.isEmpty, let nav = navigationController else { return }
            for recognizer in nav.view.gestureRecognizers ?? [] {
                savedNavGestureTouchTypes.append((recognizer, recognizer.allowedTouchTypes))
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            }
        } else {
            for (recognizer, types) in savedNavGestureTouchTypes { recognizer.allowedTouchTypes = types }
            savedNavGestureTouchTypes = []
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        canvas.sendSubviewToBack(pagesContainer)
        let width = view.bounds.width
        guard width > 0, layout.count > 0 else { return }
        if width != lastLayoutWidth {
            let relative = lastLayoutWidth > 0 ? canvas.zoomScale / fitScale(for: lastLayoutWidth) : pendingRelativeZoom
            let anchorPage = lastLayoutWidth > 0 ? currentPageIndex : (pendingScrollPage ?? 0)
            lastLayoutWidth = width
            applyZoomLimits()
            canvas.zoomScale = clampZoom(fitScale(for: width) * relative)
            updateGeometry()
            scrollTo(pageIndex: anchorPage, animated: false)
            pendingScrollPage = nil
        } else {
            updateGeometry()
        }
        if canvas.window != nil, !canvas.isFirstResponder, presentedViewController == nil {
            activateToolPicker()
        }
    }

    // MARK: Loading pages and ink

    /// Shows `pages` with their backgrounds and ink (page coordinates, keyed by page ID).
    /// Called once when the document opens and again after page edits (insert, move, delete…).
    func load(pageIDs: [UUID], sources: [PageBackgroundSource], drawings: [UUID: PKDrawing],
              darkPaper: Bool, scrollToPage: Int? = nil, relativeZoom: CGFloat? = nil) {
        isLoading = true
        defer { isLoading = false }

        self.pageIDs = pageIDs
        self.sources = sources
        layout = PageStackLayout(sizes: sources.map { PageSize(width: Double($0.size.width), height: Double($0.size.height)) })

        let style: UIUserInterfaceStyle = darkPaper ? .dark : .light
        canvas.overrideUserInterfaceStyle = style
        toolPicker.colorUserInterfaceStyle = style

        var merged = PKDrawing()
        for (i, id) in pageIDs.enumerated() {
            guard let page = drawings[id], !page.strokes.isEmpty else { continue }
            let frame = layout.frames[i]
            merged.append(page.transformed(using: CGAffineTransform(translationX: frame.x, y: frame.y)))
        }
        canvas.drawing = merged
        canvas.undoManager?.removeAllActions()

        for view in pageViews.values { view.removeFromSuperview() }
        pageViews = [:]
        pagesContainer.bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)

        if let relativeZoom { pendingRelativeZoom = relativeZoom }
        if lastLayoutWidth > 0 {
            applyZoomLimits()
            if let relativeZoom { canvas.zoomScale = clampZoom(fitScale(for: lastLayoutWidth) * relativeZoom) }
            updateGeometry()
            if let scrollToPage { scrollTo(pageIndex: scrollToPage, animated: false) }
        } else {
            pendingScrollPage = scrollToPage
            viewIfLoaded?.setNeedsLayout()
        }
    }

    /// The canvas drawing cut into pages, in page coordinates. A stroke belongs to the page
    /// under the middle of its bounds (strokes in a gap go to the nearer page).
    func splitDrawing() -> [UUID: PKDrawing] {
        var buckets = Array(repeating: [PKStroke](), count: pageIDs.count)
        for stroke in canvas.drawing.strokes {
            guard let i = layout.pageIndex(forY: Double(stroke.renderBounds.midY)) else { continue }
            buckets[i].append(stroke)
        }
        var result: [UUID: PKDrawing] = [:]
        for (i, strokes) in buckets.enumerated() {
            let frame = layout.frames[i]
            result[pageIDs[i]] = strokes.isEmpty
                ? PKDrawing()
                : PKDrawing(strokes: strokes).transformed(using: CGAffineTransform(translationX: -frame.x, y: -frame.y))
        }
        return result
    }

    // MARK: Zoom and geometry

    private func fitScale(for width: CGFloat) -> CGFloat {
        max(0.1, width / CGFloat(layout.width))
    }

    /// Zoom 50–500 % of fit width (fit width on a 13″ Air in portrait is about real size).
    private func applyZoomLimits() {
        let fit = fitScale(for: lastLayoutWidth)
        canvas.minimumZoomScale = fit * 0.5
        canvas.maximumZoomScale = fit * 5
    }

    private func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, canvas.minimumZoomScale), canvas.maximumZoomScale)
    }

    /// Zoom relative to fit width, for remembering per document.
    var relativeZoom: CGFloat {
        lastLayoutWidth > 0 ? canvas.zoomScale / fitScale(for: lastLayoutWidth) : pendingRelativeZoom
    }

    private func updateGeometry() {
        let zoom = canvas.zoomScale
        pagesContainer.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        pagesContainer.layer.position = .zero
        let contentSize = CGSize(width: CGFloat(layout.width) * zoom, height: CGFloat(layout.height) * zoom)
        if canvas.contentSize != contentSize { canvas.contentSize = contentSize }
        // Centre the pages when they are narrower than the view; leave room for the tool picker.
        let side = max(0, (canvas.bounds.width - contentSize.width) / 2)
        let insets = UIEdgeInsets(top: 0, left: side, bottom: bottomObscured, right: side)
        if canvas.contentInset != insets { canvas.contentInset = insets }
        updateVisiblePages()
    }

    func scrollTo(pageIndex: Int, animated: Bool) {
        guard layout.frames.indices.contains(pageIndex) else { return }
        let zoom = canvas.zoomScale
        let maxY = max(-canvas.contentInset.top, canvas.contentSize.height + canvas.contentInset.bottom - canvas.bounds.height)
        let y = min(maxY, max(-canvas.contentInset.top, (CGFloat(layout.frames[pageIndex].y) - 12) * zoom))
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: y), animated: animated)
        if !animated { updateVisiblePages() }
    }

    /// Keeps tiled views only for the pages on screen ±2, so a 120-page PDF stays light.
    private func updateVisiblePages() {
        guard layout.count > 0, canvas.bounds.height > 0 else { return }
        let zoom = max(canvas.zoomScale, 0.01)
        let top = Double(canvas.contentOffset.y / zoom)
        let bottom = Double((canvas.contentOffset.y + canvas.bounds.height) / zoom)
        guard let range = layout.pages(intersecting: top, bottom, extra: 2) else { return }
        let wanted = Set(range.map { pageIDs[$0] })
        for (id, view) in pageViews where !wanted.contains(id) {
            view.removeFromSuperview()
            pageViews[id] = nil
        }
        for i in range where pageViews[pageIDs[i]] == nil {
            let view = TiledPageView(source: sources[i])
            let f = layout.frames[i]
            view.frame = CGRect(x: f.x, y: f.y, width: f.width, height: f.height)
            pagesContainer.addSubview(view)
            pageViews[pageIDs[i]] = view
        }
        // The current page is the one under a line a third of the way down the screen.
        let probe = top + (bottom - top) / 3
        if let current = layout.pageIndex(forY: probe), current != currentPageIndex {
            currentPageIndex = current
            delegate?.inkCanvasCurrentPageDidChange(current)
        }
    }

    // MARK: PKCanvasViewDelegate / UIScrollViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isLoading else { return }
        delegate?.inkCanvasDrawingDidChange()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateGeometry()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisiblePages()
    }

    // MARK: PKToolPickerObserver

    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        let obscured = toolPicker.frameObscured(in: view)
        bottomObscured = obscured.isNull ? 0 : max(0, view.bounds.maxY - obscured.minY)
        updateGeometry()
    }

    // MARK: Undo

    var canUndo: Bool { canvas.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvas.undoManager?.canRedo ?? false }

    func undo() {
        canvas.undoManager?.undo()
    }

    func redo() {
        canvas.undoManager?.redo()
    }

    @objc private func twoFingerTap() { undo() }
    @objc private func threeFingerTap() { redo() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
