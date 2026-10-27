import TerminalEmulation

/// The quads of one row: the backgrounds that differ from the default, the
/// glyphs, and the lines of the cells. Positions count from the top left of the row, so a row that
/// moves down the screen keeps its quads.
struct RowQuads {
    private(set) var backgrounds: [CellQuad] = []
    private(set) var glyphs: [CellQuad] = []
    private(set) var decorations: [CellQuad] = []

    init(row: RenderRow, colors: RenderColors, atlas: GlyphAtlas, metrics: CellMetrics) throws {
        try row.forEachCell(palette: colors.palette) { cell in
            let x = Int(cell.column) * metrics.width
            if let background = cell.background, background != colors.background {
                backgrounds.append(.rectangle(x: x, y: 0, width: metrics.width, height: metrics.height, color: background))
            }
            let foreground = cell.foreground ?? colors.foreground
            decorations += DecorationQuads.lines(for: cell, x: x, color: foreground, metrics: metrics)
            // The second cell of a wide character has nothing to draw.
            guard let base = cell.base, base != " ", cell.width != .wideTail, cell.width != .wideHead else { return }
            let key = GlyphKey(text: cell.text, face: FontFace(style: cell.style), columns: cell.width == .wide ? 2 : 1)
            let entry = atlas.entry(for: key)
            if !entry.isEmpty { glyphs.append(.glyph(entry, x: x, y: 0, color: foreground)) }
        }
    }
}
