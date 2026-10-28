import TerminalEmulation

/// The quadrilaterals of one row: the backgrounds that differ from the default, the
/// glyphs, and the lines of the cells. Positions count from the top left of
/// the row, so a row that moves down the screen keeps its quadrilaterals.
struct RowQuadrilaterals {
    private(set) var backgrounds: [CellQuadrilateral] = []
    private(set) var glyphs: [CellQuadrilateral] = []
    private(set) var decorations: [CellQuadrilateral] = []
    /// The columns of the wide characters. A cursor on one of them covers 2 cells.
    private(set) var wideColumns: [UInt16] = []

    init(row: RenderRow, colors: RenderColors, selection: TerminalColor, atlas: GlyphAtlas, metrics: CellMetrics,
         rowIndex: Int = 0, padding: Int = 0, viewportSize: (width: Int, height: Int)? = nil) throws {
        let selected = row.selectedColumns
        func entry(for key: GlyphKey, at horizontalPosition: Int) -> GlyphAtlas.Entry {
            guard let viewportSize else { return atlas.entry(for: key) }
            return atlas.entry(for: key, at: (padding + horizontalPosition, padding + rowIndex * metrics.height),
                               within: viewportSize)
        }
        try row.forEachCell(palette: colors.palette) { cell in
            let horizontalPosition = Int(cell.column) * metrics.width
            var foreground = cell.foreground ?? colors.foreground
            var background = cell.background
            if cell.style.isInverse { (foreground, background) = (background ?? colors.background, foreground) }
            if selected?.contains(cell.column) == true { background = selection }
            if let background, background != colors.background {
                backgrounds.append(.rectangle(horizontalPosition: horizontalPosition, verticalPosition: 0,
                                              width: metrics.width, height: metrics.height, color: background))
            }
            if cell.style.isFaint { foreground = Self.halfway(foreground, background ?? colors.background) }
            decorations += DecorationQuadrilaterals.lines(for: cell, horizontalPosition: horizontalPosition, color: foreground, metrics: metrics)
            if cell.width == .wide { wideColumns.append(cell.column) }
            // The second cell of a wide character has nothing to draw.
            if let base = cell.base, base != " ", !cell.style.isInvisible, cell.width != .wideTail, cell.width != .wideHead {
                // Most cells hold one scalar, and a short string needs no memory from the heap.
                let text = cell.extraScalars.isEmpty ? String(Character(base)) : cell.text
                let key = GlyphKey(text: text, face: FontFace(style: cell.style), columns: cell.width == .wide ? 2 : 1)
                let entry = entry(for: key, at: horizontalPosition)
                if !entry.isEmpty {
                    glyphs.append(.glyph(entry, column: Int(cell.column), horizontalPosition: horizontalPosition, verticalPosition: 0, color: foreground))
                }
            }
            // The wave goes after the text, so the first glyph of a column is its text.
            if cell.style.underline == .curly {
                glyphs.append(.glyph(entry(for: .curlyUnderline, at: horizontalPosition), column: Int(cell.column), horizontalPosition: horizontalPosition,
                                     verticalPosition: 0, color: cell.underlineColor ?? foreground))
            }
        }
    }

    /// Faint text has half of the strength of its color against the background.
    private static func halfway(_ first: TerminalColor, _ second: TerminalColor) -> TerminalColor {
        TerminalColor(
            red: UInt8((Int(first.red) + Int(second.red)) / 2), green: UInt8((Int(first.green) + Int(second.green)) / 2),
            blue: UInt8((Int(first.blue) + Int(second.blue)) / 2))
    }
}
