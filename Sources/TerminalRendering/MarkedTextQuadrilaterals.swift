import Foundation
import TerminalEmulation

/// The quadrilaterals of the text that an input method composes. The text is not in the
/// terminal until the input method commits it. The renderer draws it from the
/// cursor, over a background that hides the cells below, and with a thick
/// underline. Text continues on the next row at the right edge.
struct MarkedTextQuadrilaterals {
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

    private(set) var backgrounds: [CellQuadrilateral] = []
    private(set) var glyphs: [CellQuadrilateral] = []
    private(set) var overlays: [CellQuadrilateral] = []
    /// The columns that the marked text covers on each row.
    private(set) var coveredColumns: [Int: Range<Int>] = [:]

    init(
        text: String, column: Int, row: Int, columnCount: Int, rowCount: Int, colors: RenderColors, atlas: GlyphAtlas,
        metrics: CellMetrics, padding: Int, selection: NSRange? = nil, selectionColor: TerminalColor? = nil,
        viewportSize: (width: Int, height: Int)? = nil
    ) {
        let layout = Layout(text: text, column: column, row: row, columnCount: columnCount, rowCount: rowCount, selection: selection, atlas: atlas)
        for character in layout.characters where character.row >= 0 && character.row < rowCount {
            let horizontalPosition = padding + character.column * metrics.width
            let top = padding + character.row * metrics.height
            let width = character.width * metrics.width
            let background = layout.selection.overlaps(character.range) ? (selectionColor ?? colors.foreground) : colors.background
            backgrounds.append(.rectangle(horizontalPosition: horizontalPosition, verticalPosition: top,
                                          width: width, height: metrics.height, color: background))
            let key = GlyphKey(text: character.text, face: .regular, columns: character.width)
            let entry: GlyphAtlas.Entry
            if let viewportSize {
                entry = atlas.entry(for: key, at: (horizontalPosition, top), within: viewportSize)
            } else {
                entry = atlas.entry(for: key)
            }
            if !entry.isEmpty {
                glyphs.append(.glyph(entry, column: character.column, horizontalPosition: horizontalPosition,
                                     verticalPosition: top, color: colors.foreground))
            }
            overlays.append(.rectangle(horizontalPosition: horizontalPosition, verticalPosition: top + metrics.underlinePosition, width: width,
                                       height: 2 * metrics.underlineThickness, color: colors.foreground))
            let start = coveredColumns[character.row]?.lowerBound ?? character.column
            coveredColumns[character.row] = start..<character.column + character.width
        }
        if layout.selection.isEmpty, layout.caret.row >= 0, layout.caret.row < rowCount {
            let thickness = max(1, metrics.underlineThickness)
            let horizontalPosition = padding + layout.caret.column * metrics.width - (layout.caret.column == columnCount ? thickness : 0)
            overlays.append(.rectangle(horizontalPosition: horizontalPosition, verticalPosition: padding + layout.caret.row * metrics.height,
                                       width: thickness, height: metrics.height, color: colors.cursor ?? colors.foreground))
        }
    }
}
