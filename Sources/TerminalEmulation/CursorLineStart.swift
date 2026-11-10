import GhosttyVt

extension Terminal {
    /// Whether the cursor is at the start of a blank row, where a line break
    /// after a reflow can give it a row of its own again.
    ///
    /// zsh's prompt can start on a row that continues the output above it:
    /// after output without a line end, the mark of PROMPT_SP and its spaces
    /// wrap onto a new row. When zsh answers a new size, it erases from the
    /// first column of that row. A reflow then joins the blank row to the
    /// output, and the cursor stands after the output, where zsh would draw
    /// its prompt. A line break after the reflow moves the cursor to a new
    /// row and erases no cell. At the bottom, the new row takes the
    /// background of the cursor's style, so that style must have none.
    ///
    /// Ordinary output keeps the reflow of libghostty-vt. Only a size that
    /// comes where a shell has erased its lines does this.
    var cursorStartsBlankRow: Bool {
        let cursor = cursorPosition
        return cursor.column == 0 && !isAlternateScreenActive && isAtVirtualTerminalGround && !cursorStyleHasBackground
            && (0..<size.columns).allSatisfy { cellIsBlank(column: $0, activeRow: Int(cursor.row)) }
    }

    /// Erases a prompt that the shell has not drawn again after a new size,
    /// from its first row down, and puts the cursor at the start of that row.
    /// Returns false, and erases nothing, when the screen cannot take bytes.
    ///
    /// Blank rows do not reflow. So after the resize, the cursor can go the
    /// same number of rows below that first row again, and the late answer of
    /// the shell lands on the prompt. kitty keeps a prompt in this way.
    func erasePrompt(rowsAboveCursor rows: Int) -> Bool {
        let firstRow = Int(cursorPosition.row) - rows
        guard rows >= 0, firstRow >= 0, !isAlternateScreenActive, isAtVirtualTerminalGround, !isOriginModeEnabled, !cursorStyleHasBackground
        else { return false }
        write("\u{1b}[\(firstRow + 1);1H\u{1b}[J")
        return true
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
