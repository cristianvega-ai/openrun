/// The quads of one frame, in the order of drawing: the backgrounds, the glyphs,
/// and then the lines on top of the glyphs.
struct FrameBuilder {
    private(set) var backgrounds: [CellQuad] = []
    private(set) var glyphs: [CellQuad] = []
    private(set) var overlays: [CellQuad] = []

    /// Moves the quads of each row to its place on the screen: down by the
    /// rows above it, and in by the padding.
    init(cache: RowCache, metrics: CellMetrics, padding: Int) {
        for index in cache.order.indices {
            guard let row = cache.quads(at: index) else { continue }
            let top = padding + index * metrics.height
            backgrounds += row.backgrounds.map { $0.moved(x: padding, y: top) }
            glyphs += row.glyphs.map { $0.moved(x: padding, y: top) }
            overlays += row.decorations.map { $0.moved(x: padding, y: top) }
        }
    }
}
