import GhosttyVt

/// A picture of the visible screen for a renderer. It keeps its rows between
/// updates and knows which rows changed since the renderer last drew them.
///
/// Only `beginUpdate(from:)` touches the terminal. Everything else reads
/// memory that the render state owns, so a caller that shares the terminal
/// with another thread holds its lock for `beginUpdate` alone.
public final class RenderState {
    let handle: GhosttyRenderState
    private let rowIterator: GhosttyRenderStateRowIterator
    private let rowCells: GhosttyRenderStateRowCells

    public init() throws {
        var state: GhosttyRenderState?
        try TerminalEmulationError.check(ghostty_render_state_new(nil, &state), from: "ghostty_render_state_new")
        var iterator: GhosttyRenderStateRowIterator?
        var cells: GhosttyRenderStateRowCells?
        guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS,
              ghostty_render_state_row_cells_new(nil, &cells) == GHOSTTY_SUCCESS,
              let iterator, let cells, let state
        else {
            ghostty_render_state_row_iterator_free(iterator)
            ghostty_render_state_free(state)
            throw TerminalEmulationError.invalidValue(in: "RenderState.init")
        }
        handle = state
        rowIterator = iterator
        rowCells = cells
    }

    deinit {
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(handle)
    }

    /// Takes the state of the terminal in one step.
    public func update(from terminal: Terminal) throws {
        try TerminalEmulationError.check(ghostty_render_state_update(handle, terminal.handle), from: "ghostty_render_state_update")
    }

    /// The part of an update that reads the terminal. Hold the lock of the
    /// terminal for this call only, then call `endUpdate`.
    public func beginUpdate(from terminal: Terminal) throws {
        try TerminalEmulationError.check(ghostty_render_state_begin_update(handle, terminal.handle), from: "ghostty_render_state_begin_update")
    }

    /// Finishes an update without the terminal.
    public func endUpdate() {
        _ = ghostty_render_state_end_update(handle)
    }

    /// Marks every row as drawn. Call it after a whole frame was drawn.
    public func markClean() {
        _ = ghostty_render_state_clean(handle)
    }

    public var dirtiness: RenderDirtiness {
        var dirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        _ = ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirty)
        switch dirty {
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL: return .someRows
        case GHOSTTY_RENDER_STATE_DIRTY_FULL: return .everything
        default: return .nothing
        }
    }

    public var size: TerminalSize {
        var columns: UInt16 = 0
        var rows: UInt16 = 0
        _ = ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_COLS, &columns)
        _ = ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows)
        return TerminalSize(columns: columns, rows: rows)
    }

    public var colors: RenderColors {
        var colors = GhosttyRenderStateColors()
        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
        _ = ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors)
        let palette = withUnsafeBytes(of: colors.palette) { raw in
            raw.bindMemory(to: GhosttyColorRgb.self).map(TerminalColor.init)
        }
        return RenderColors(
            background: TerminalColor(colors.background),
            foreground: TerminalColor(colors.foreground),
            cursor: colors.cursor_has_value ? TerminalColor(colors.cursor) : nil,
            palette: palette
        )
    }

    public var cursor: RenderCursor {
        var cursor = GhosttyRenderStateCursor()
        cursor.size = MemoryLayout<GhosttyRenderStateCursor>.size
        _ = ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor)
        return RenderCursor(
            position: cursor.viewport_has_value
                ? TerminalCursorPosition(column: cursor.viewport_x, row: cursor.viewport_y) : nil,
            isOnWideCharacterTail: cursor.viewport_has_value && cursor.wide_tail,
            isVisible: cursor.visible,
            isBlinking: cursor.blinking,
            isAtPasswordInput: cursor.password_input,
            style: CursorStyle(cursor.visual_style)
        )
    }

    /// Calls `body` for each row from the top. A `RenderRow` is valid only
    /// inside `body`, because the next update reuses its memory.
    ///
    /// - Parameter onlyChanged: Visits only the rows that changed, or every
    ///   row when the whole picture changed.
    public func forEachRow(onlyChanged: Bool, _ body: (RenderRow) throws -> Void) throws {
        var iterator: GhosttyRenderStateRowIterator? = rowIterator
        try TerminalEmulationError.check(
            ghostty_render_state_get(handle, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator),
            from: "ghostty_render_state_get"
        )
        let row = RenderRow(iterator: rowIterator, cells: rowCells)
        var viewportRow: UInt16 = 0
        while onlyChanged
            ? ghostty_render_state_row_iterator_next_dirty(rowIterator, &viewportRow)
            : ghostty_render_state_row_iterator_next(rowIterator) {
            try body(row)
        }
    }
}
