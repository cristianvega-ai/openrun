import GhosttyVt

/// A picture of the visible screen for a renderer. It keeps its rows between
/// updates and knows which rows changed since the renderer last drew them.
///
/// Only `beginUpdate(from:)` touches the terminal. Everything else reads
/// memory that the render state owns, so a caller that shares the terminal
/// with another thread holds its lock for `beginUpdate` alone.
public final class RenderState {
    let handle: GhosttyRenderState

    public init() throws {
        var state: GhosttyRenderState?
        try TerminalEmulationError.check(ghostty_render_state_new(nil, &state), from: "ghostty_render_state_new")
        guard let state else {
            throw TerminalEmulationError.invalidValue(in: "RenderState.init")
        }
        handle = state
    }

    deinit {
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
}
