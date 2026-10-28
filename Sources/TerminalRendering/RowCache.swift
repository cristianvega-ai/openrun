import TerminalEmulation

/// Keeps the `RowQuadrilaterals` of the rows on the screen by their `RowIdentifier`,
/// so a row that did not change is not read again.
struct RowCache {
    /// The identifiers of the rows, from the top row down.
    private(set) var order: [RowIdentifier] = []
    private var rows: [RowIdentifier: RowQuadrilaterals] = [:]
    private var size: TerminalSize?
    private var colors: RenderColors?

    func quads(at index: Int) -> RowQuadrilaterals? {
        rows[order[index]]
    }

    /// Makes the next update read every row, as when something besides the
    /// screen changes the quads.
    mutating func forget() {
        size = nil
    }

    /// Makes new quads for the rows that changed. Every row changes when the
    /// whole screen is dirty, when the grid has a new size, or when the colors
    /// change.
    ///
    /// - Parameters:
    ///   - colors: The colors of `state`. The caller reads them once for the frame, and the rows use them too.
    ///   - make: Makes the quads of a row that the cache must read.
    mutating func update(
        from state: RenderState, colors: RenderColors, make: (RenderRow) throws -> RowQuadrilaterals
    ) throws -> FrameStatistics {
        let rebuildAll = state.dirtiness == .everything || state.size != size || colors != self.colors
        (size, self.colors) = (state.size, colors)
        var statistics = FrameStatistics()
        var kept: [RowIdentifier: RowQuadrilaterals] = [:]
        var order: [RowIdentifier] = []
        try state.forEachRow(onlyChanged: false) { row in
            let identifier = row.identifier
            order.append(identifier)
            if !rebuildAll, !row.isDirty, let known = rows[identifier] {
                kept[identifier] = known
                statistics.rowsReused += 1
            } else {
                kept[identifier] = try make(row)
                statistics.rowsPrepared += 1
            }
        }
        (rows, self.order) = (kept, order)
        return statistics
    }
}
