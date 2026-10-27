import TerminalEmulation

/// The quads of one frame, in the order of drawing: the backgrounds, the glyphs,
/// and then the lines on top of the glyphs.
struct FrameBuilder {
    /// The cursor as the renderer shows it.
    struct Cursor {
        let column: Int
        let row: Int
        let style: CursorStyle
        let isOnWideCharacterTail: Bool
        let color: TerminalColor
        /// The color of the glyph in a block cursor, so that it stays readable.
        let textColor: TerminalColor
        let stroke: Int
    }

    private(set) var backgrounds: [CellQuad] = []
    private(set) var glyphs: [CellQuad] = []
    private(set) var overlays: [CellQuad] = []

    /// Moves the quads of each row to its place on the screen: down by the
    /// rows above it, and in by the space around the grid.
    init(cache: RowCache, metrics: CellMetrics, padding: Int, cursor: Cursor? = nil, markedText: MarkedTextQuads? = nil) {
        for index in cache.order.indices {
            guard let row = cache.quads(at: index) else { continue }
            let top = padding + index * metrics.height
            let glyphStart = glyphs.count
            backgrounds += row.backgrounds.map { $0.moved(x: padding, y: top) }
            // The background of marked text hides the glyphs under it.
            let covered = markedText?.row == index ? markedText?.columns : nil
            let visible = covered.map { columns in row.glyphs.filter { !columns.contains(Int($0.column)) } } ?? row.glyphs
            glyphs += visible.map { $0.moved(x: padding, y: top) }
            overlays += row.decorations.map { $0.moved(x: padding, y: top) }
            guard let cursor, cursor.row == index else { continue }
            // On the second cell of a wide character, the cursor starts one column to the left.
            let column = cursor.column - (cursor.isOnWideCharacterTail ? 1 : 0)
            let isWide = cursor.isOnWideCharacterTail || row.wideColumns.contains(UInt16(column))
            let quads = CursorQuads(
                style: cursor.style, x: padding + column * metrics.width, y: top, width: (isWide ? 2 : 1) * metrics.width,
                height: metrics.height, stroke: cursor.stroke, color: cursor.color)
            backgrounds += quads.backgrounds
            overlays += quads.overlays
            if cursor.style == .block, let glyph = glyphs[glyphStart...].firstIndex(where: { Int($0.column) == column }) {
                glyphs[glyph].color = CellQuad.vector(cursor.textColor)
            }
        }
        if let markedText {
            backgrounds += markedText.backgrounds
            glyphs += markedText.glyphs
            overlays += markedText.overlays
        }
    }
}
