import SwiftUI
import PencilKit

/// The writing area for a review attempt: Pencil draws, a finger scrolls, and the paper grows
/// by another screen whenever you write near the bottom.
struct AttemptCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var undoTrigger: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if canvas.drawing != drawing { canvas.drawing = drawing }
        if canvas.bounds.height > 0 { c.ensureHeight(canvas) }
        if undoTrigger != c.lastUndo {
            c.lastUndo = undoTrigger
            canvas.undoManager?.undo()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: AttemptCanvas
        var picker: PKToolPicker?
        var lastUndo = 0
        init(_ parent: AttemptCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            ensureHeight(canvasView)
        }

        /// Always keep at least one extra screen of paper below the lowest stroke.
        func ensureHeight(_ canvas: PKCanvasView) {
            let screen = max(canvas.bounds.height, 400)
            let lowest = canvas.drawing.bounds.isEmpty ? 0 : canvas.drawing.bounds.maxY
            let needed = max(screen, lowest + screen * 0.8)
            if canvas.contentSize.height < needed || canvas.contentSize.width != canvas.bounds.width {
                canvas.contentSize = CGSize(width: canvas.bounds.width, height: needed)
            }
        }
    }
}
