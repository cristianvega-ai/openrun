import GhosttyVt

/// One row of a `RenderState`, valid only while the state calls the body
/// that received it.
public struct RenderRow {
    private let iterator: GhosttyRenderStateRowIterator

    init(iterator: GhosttyRenderStateRowIterator) {
        self.iterator = iterator
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
}
