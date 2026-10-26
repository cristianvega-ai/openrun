import GhosttyVt

/// One row of a `RenderState`, valid only while the state calls the body
/// that received it.
public struct RenderRow {
    private let iterator: GhosttyRenderStateRowIterator
    private let cells: GhosttyRenderStateRowCells

    init(iterator: GhosttyRenderStateRowIterator, cells: GhosttyRenderStateRowCells) {
        self.iterator = iterator
        self.cells = cells
    }

    /// The identity of the row across updates. A renderer keeps its prepared
    /// rows by this identifier and reuses one while the row is not dirty.
    public var identifier: RowIdentifier {
        var identifier = GhosttyRenderStateRowId()
        _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_ID, &identifier)
        return RowIdentifier(first: identifier.bits.0, second: identifier.bits.1)
    }

    /// The place of the row from the top of the visible screen.
    public var viewportRow: Int {
        var row: Int32 = 0
        _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_VIEWPORT_Y, &row)
        return Int(row)
    }

    public var isDirty: Bool {
        var dirty = false
        _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &dirty)
        return dirty
    }

    /// Calls `body` for each cell from the left.
    public func forEachCell(_ body: (RenderCell) throws -> Void) throws {
        var handle: GhosttyRenderStateRowCells? = cells
        try TerminalEmulationError.check(
            ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &handle),
            from: "ghostty_render_state_row_get"
        )
        var column: UInt16 = 0
        var codepoints = [UInt32](repeating: 0, count: 16)
        while ghostty_render_state_row_cells_next(cells) {
            defer { column += 1 }
            var raw: GhosttyCell = 0, length: UInt32 = 0
            var wide = GHOSTTY_CELL_WIDE_NARROW
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw)
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &length)
            _ = ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
            // One buffer serves every cell, because most cells hold one scalar.
            let count = Int(length)
            if count > codepoints.count { codepoints = [UInt32](repeating: 0, count: count) }
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, &codepoints)
            let scalars = codepoints.prefix(count).compactMap(Unicode.Scalar.init)
            try body(RenderCell(column: column, base: scalars.first, extraScalars: Array(scalars.dropFirst()), width: CellWidth(wide)))
        }
    }
}
