import Foundation
import TerminalEmulation

/// The quads of the text that an input method composes. The text is not in the
/// terminal until the input method commits it. The renderer draws it from the
/// cursor to the right, over a background that hides the cells below, and with
/// a thick underline.
struct MarkedTextQuads {
    struct Layout {
        struct CharacterPosition {
            let text: String
            let column, row, width: Int
            let range: Range<Int>
        }

        let characters: [CharacterPosition]
        let caret: (column: Int, row: Int)
        let selection: Range<Int>

        init(text: String, column: Int, row: Int, columnCount: Int, rowCount: Int, selection: NSRange?, atlas: GlyphAtlas) {
            let length = text.utf16.count
            let start = selection.flatMap { $0.location == NSNotFound ? nil : min(max(0, $0.location), length) } ?? length
            let count = min(max(0, selection?.length ?? 0), length - start)
            self.selection = start..<start + count
            var positions: [CharacterPosition] = []
            var nextColumn = column, nextRow = row, offset = 0
            var caret: (column: Int, row: Int)?
            for character in text {
                let cluster = String(character)
                let width = min(atlas.columns(of: cluster), columnCount)
                if nextColumn + width > columnCount { nextColumn = 0; nextRow += 1 }
                let end = offset + cluster.utf16.count
                if caret == nil, start < end { caret = (nextColumn, nextRow) }
                positions.append(CharacterPosition(text: cluster, column: nextColumn, row: nextRow, width: width, range: offset..<end))
                nextColumn += width
                offset = end
            }
            let position: (column: Int, row: Int) = caret ?? (nextColumn, nextRow)
            // Keep the selected position visible when the text is taller than the grid.
            let shift = min(max(0, nextRow - rowCount + 1), position.row)
            characters = positions.map {
                CharacterPosition(text: $0.text, column: $0.column, row: $0.row - shift, width: $0.width, range: $0.range)
            }
            self.caret = (position.column, position.row - shift)
        }
    }

    private(set) var backgrounds: [CellQuad] = []
    private(set) var glyphs: [CellQuad] = []
    private(set) var overlays: [CellQuad] = []
    /// The columns of the row that the text covers.
    private(set) var columns: Range<Int>
    let row: Int
    var coveredColumns: [Int: Range<Int>] { columns.isEmpty ? [:] : [row: columns] }

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
