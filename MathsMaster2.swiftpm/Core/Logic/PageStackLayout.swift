import Foundation

/// The editor shows a document as one vertical stack of pages in a single coordinate space
/// (points, unzoomed), with a gap between pages (design plan §3.2). Ink is drawn in this space
/// and split back into page coordinates for storage (§3.1: strokes are stored per page).
struct PageStackLayout: Equatable, Sendable {
    static let gap: Double = 24
    static let margin: Double = 24

    /// Page rectangles in stack coordinates.
    private(set) var frames: [Rect]
    /// Total size of the stack, margins included.
    private(set) var width: Double
    private(set) var height: Double

    init(sizes: [PageSize], gap: Double = PageStackLayout.gap, margin: Double = PageStackLayout.margin) {
        let widest = sizes.map(\.width).max() ?? PageSize.a4Portrait.width
        var y = margin
        var frames: [Rect] = []
        frames.reserveCapacity(sizes.count)
        for size in sizes {
            frames.append(Rect(x: margin + (widest - size.width) / 2, y: y, width: size.width, height: size.height))
            y += size.height + gap
        }
        self.frames = frames
        self.width = widest + 2 * margin
        self.height = sizes.isEmpty ? 2 * margin : y - gap + margin
    }

    var count: Int { frames.count }

    /// The page a point at height `y` belongs to: the page containing it, otherwise the nearest
    /// (the boundary between two pages is the middle of the gap). Nil only for an empty stack.
    func pageIndex(forY y: Double) -> Int? {
        guard !frames.isEmpty else { return nil }
        var lo = 0
        var hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            let boundary = (frames[mid].maxY + frames[mid + 1].y) / 2
            if y < boundary { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    /// Pages that intersect the band `minY...maxY`, widened by `extra` pages either side.
    func pages(intersecting minY: Double, _ maxY: Double, extra: Int = 0) -> ClosedRange<Int>? {
        guard let first = pageIndex(forY: minY), let last = pageIndex(forY: maxY) else { return nil }
        return max(0, first - extra)...min(frames.count - 1, last + extra)
    }
}

extension Rect {
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }
}
