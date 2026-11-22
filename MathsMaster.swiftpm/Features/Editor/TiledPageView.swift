import UIKit

/// A tiled layer that draws one page background. CATiledLayer re-renders tiles at the zoom
/// level on screen, so PDF text and template lines stay sharp at 400 % (design plan §3.10).
/// Drawing happens on background threads, so it only reads the immutable `source`.
final class PageTileLayer: CATiledLayer {
    var source: PageBackgroundSource?

    override init() {
        super.init()
    }

    /// Core Animation copies layers (presentation layers) through this initialiser.
    override init(layer: Any) {
        super.init(layer: layer)
        source = (layer as? PageTileLayer)?.source
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override class func fadeDuration() -> CFTimeInterval { 0.08 }

    override func draw(in ctx: CGContext) {
        guard let source else { return }
        // The layer's bounds are the page size in points, so page coordinates map 1:1.
        PageRenderer.draw(source, in: ctx, clip: ctx.boundingBoxOfClipPath)
    }
}

/// The background of one page in the editor's page stack, sized in page points.
/// The stack's container is scaled by the zoom, and the tiles follow.
final class TiledPageView: UIView {
    override class var layerClass: AnyClass { PageTileLayer.self }

    private var tileLayer: PageTileLayer { layer as! PageTileLayer }

    init(source: PageBackgroundSource) {
        super.init(frame: CGRect(origin: .zero, size: source.size))
        isUserInteractionEnabled = false
        isOpaque = true
        let screenScale = UIScreen.main.scale
        tileLayer.tileSize = CGSize(width: 512 * screenScale, height: 512 * screenScale)
        // 2^4 = 16× magnified detail covers 400 % zoom on a 2× screen with headroom.
        tileLayer.levelsOfDetail = 6
        tileLayer.levelsOfDetailBias = 4
        tileLayer.contentsScale = screenScale
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        setSource(source)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSource(_ source: PageBackgroundSource) {
        tileLayer.source = source
        backgroundColor = Self.placeholderColour(source)
        bounds = CGRect(origin: .zero, size: source.size)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        tileLayer.setNeedsDisplay()
    }

    private static func placeholderColour(_ source: PageBackgroundSource) -> UIColor {
        if case .template(let t) = source.content { return PageRenderer.paperColour(t.paper, forPrint: false) }
        return .white
    }
}
