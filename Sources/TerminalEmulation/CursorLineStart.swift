import GhosttyVt

extension Terminal {
    /// Ends the wrap of the row above the cursor, when the cursor is at the
    /// start of a blank row that continues that row.
    ///
    /// zsh's prompt can start on such a row: after output without a line end,
    /// the mark of PROMPT_SP and its spaces wrap onto a new row. When zsh
    /// answers a new size, it erases from the first column of that row. A
    /// reflow would then join the blank row to the output above it and put
    /// the cursor after that output, where zsh would draw its prompt. An
    /// erase of the last cell of the row above ends the wrap, so the cursor
    /// keeps a row of its own. Only a blank cell without style or link may
    /// go, and the erase must leave it so: the erase fills the cell with the
    /// background of the cursor's style.
    ///
    /// Ordinary output keeps the reflow of libghostty-vt. Only a size that
    /// comes where a shell has erased its lines does this.
    func keepCursorAtLineStart() {
        let cursor = cursorPosition
        let row = Int(cursor.row)
        let lastColumn = size.columns - 1
        guard cursor.column == 0, row > 0, !isAlternateScreenActive, isAtVirtualTerminalGround, !isOriginModeEnabled,
              !cursorStyleHasBackground, rowWraps(atActiveRow: row - 1), cellIsBlank(column: lastColumn, activeRow: row - 1),
              (0...lastColumn).allSatisfy({ cellIsBlank(column: $0, activeRow: row) })
        else { return }
        write("\u{1b}[\(row);\(size.columns)H\u{1b}[K\u{1b}[\(row + 1);1H")
    }

    /// Whether the parser is outside every escape sequence and character, so
    /// bytes of another source can go in without breaking one.
    private var isAtVirtualTerminalGround: Bool {
        var ground = false
        _ = ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_VT_GROUND, &ground)
        return ground
    }

    /// Origin mode makes row numbers count from the top margin.
    private var isOriginModeEnabled: Bool {
        var configuration = GhosttyTerminalModeConfig()
        configuration.mode = ghostty_mode_new(6, false)
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_MODE, &configuration) == GHOSTTY_SUCCESS else { return true }
        return configuration.value
    }

    private var cursorStyleHasBackground: Bool {
        var style = GhosttyStyle()
        style.size = MemoryLayout<GhosttyStyle>.size
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_CURSOR_STYLE, &style) == GHOSTTY_SUCCESS else { return true }
        return style.bg_color.tag != GHOSTTY_STYLE_COLOR_NONE
    }

    private func reference(column: UInt16, activeRow row: Int) -> GhosttyGridRef? {
        var point = GhosttyPoint()
        point.tag = GHOSTTY_POINT_TAG_ACTIVE
        point.value.coordinate = GhosttyPointCoordinate(x: column, y: UInt32(row))
        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        guard ghostty_terminal_grid_ref(handle, point, &reference) == GHOSTTY_SUCCESS else { return nil }
        return reference
    }

    private func rowWraps(atActiveRow row: Int) -> Bool {
        guard var reference = reference(column: 0, activeRow: row) else { return false }
        var gridRow: GhosttyRow = 0
        var wraps = false
        guard ghostty_grid_ref_row(&reference, &gridRow) == GHOSTTY_SUCCESS,
              ghostty_row_get(gridRow, GHOSTTY_ROW_DATA_WRAP, &wraps) == GHOSTTY_SUCCESS
        else { return false }
        return wraps
    }

    /// Whether the cell holds nothing or a space, without style or link.
    private func cellIsBlank(column: UInt16, activeRow row: Int) -> Bool {
        guard var reference = reference(column: column, activeRow: row) else { return false }
        var cell: GhosttyCell = 0
        var codepoint: UInt32 = 0
        var hasStyling = true
        var hasHyperlink = true
        guard ghostty_grid_ref_cell(&reference, &cell) == GHOSTTY_SUCCESS,
              ghostty_cell_get(cell, GHOSTTY_CELL_DATA_CODEPOINT, &codepoint) == GHOSTTY_SUCCESS,
              ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_STYLING, &hasStyling) == GHOSTTY_SUCCESS,
              ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_HYPERLINK, &hasHyperlink) == GHOSTTY_SUCCESS
        else { return false }
        return (codepoint == 0 || codepoint == 0x20) && !hasStyling && !hasHyperlink
    }
}
