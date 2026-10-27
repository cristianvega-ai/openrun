import TerminalEmulation

/// The quads of the text that an input method composes. The text is not in the
/// terminal until the input method commits it. The renderer draws it from the
/// cursor to the right, over a background that hides the cells below, and with
/// a thick underline.
struct MarkedTextQuads {
    private(set) var backgrounds: [CellQuad] = []
    private(set) var glyphs: [CellQuad] = []
    private(set) var overlays: [CellQuad] = []
    /// The columns of the row that the text covers.
    private(set) var columns: Range<Int>
    let row: Int

    /// - Parameter columnCount: The width of the grid. The text stops at its right edge.
    init(
        text: String, column: Int, row: Int, columnCount: Int, colors: RenderColors, atlas: GlyphAtlas, metrics: CellMetrics,
        padding: Int
    ) {
        self.row = row
        columns = column..<column
        let top = padding + row * metrics.height
        for character in text {
            let cluster = String(character)
            let width = atlas.columns(of: cluster)
            guard columns.upperBound + width <= columnCount else { break }
            let x = padding + columns.upperBound * metrics.width
            backgrounds.append(.rectangle(x: x, y: top, width: width * metrics.width, height: metrics.height, color: colors.background))
            let entry = atlas.entry(for: GlyphKey(text: cluster, face: .regular, columns: width))
            if !entry.isEmpty { glyphs.append(.glyph(entry, column: columns.upperBound, x: x, y: top, color: colors.foreground)) }
            overlays.append(
                .rectangle(
                    x: x, y: top + metrics.underlinePosition, width: width * metrics.width, height: 2 * metrics.underlineThickness,
                    color: colors.foreground))
            columns = column..<columns.upperBound + width
        }
    }
}
