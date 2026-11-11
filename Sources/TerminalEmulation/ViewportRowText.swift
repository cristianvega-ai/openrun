import GhosttyVt

/// The text of one row of the viewport, cell by cell. A caller that looks for
/// something in the text, such as a web address under the pointer, reads only
/// the rows it needs, and only when it needs them.
public struct ViewportRowText: Equatable, Sendable {
    /// The text of each cell from the left: a grapheme cluster, or an empty
    /// text for a blank cell and for the second cell of a wide character.
    public let cells: [String]
    /// The text goes on in the next row, because the row was soft-wrapped.
    public let wrapsToNextRow: Bool
    /// The text comes from the end of the row above, which was soft-wrapped.
    public let continuesPreviousRow: Bool

    public init(cells: [String], wrapsToNextRow: Bool, continuesPreviousRow: Bool) {
        (self.cells, self.wrapsToNextRow, self.continuesPreviousRow) = (cells, wrapsToNextRow, continuesPreviousRow)
    }
}

extension Terminal {
    /// The text of a row of the viewport, or `nil` for a row outside it.
    public func viewportRowText(at row: UInt32) -> ViewportRowText? {
        let size = size
        guard row < UInt32(size.rows), size.columns > 0 else { return nil }
        var codepoints = [UInt32](repeating: 0, count: 16)
        var cells: [String] = []
        cells.reserveCapacity(Int(size.columns))
        var flags = (wraps: false, continues: false)
        for column in 0..<size.columns {
            guard var reference = try? gridReference(at: ViewportCell(column: column, row: row)) else { return nil }
            if column == 0 {
                var handle: GhosttyRow = 0
                if ghostty_grid_ref_row(&reference, &handle) == GHOSTTY_SUCCESS {
                    _ = ghostty_row_get(handle, GHOSTTY_ROW_DATA_WRAP, &flags.wraps)
                    _ = ghostty_row_get(handle, GHOSTTY_ROW_DATA_WRAP_CONTINUATION, &flags.continues)
                }
            }
            var length = 0
            if ghostty_grid_ref_graphemes(&reference, &codepoints, codepoints.count, &length) == GHOSTTY_OUT_OF_SPACE {
                codepoints = [UInt32](repeating: 0, count: length)
                _ = ghostty_grid_ref_graphemes(&reference, &codepoints, codepoints.count, &length)
            }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: codepoints.prefix(length).compactMap(Unicode.Scalar.init))
            cells.append(String(text))
        }
        return ViewportRowText(cells: cells, wrapsToNextRow: flags.wraps, continuesPreviousRow: flags.continues)
    }
}
