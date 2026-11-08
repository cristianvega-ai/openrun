import CoreGraphics
import TerminalEmulation

/// Works out how many columns and rows fit in a view.
enum GridFit {
    /// - Parameters:
    ///   - size: The size of the view in points.
    ///   - scale: The number of pixels for each point.
    ///   - cell: The size of a cell in pixels.
    ///   - padding: The space around the grid in pixels.
    /// - Returns: The whole cells that fit inside the padding, and at least one
    ///   column and one row, because a terminal cannot be smaller.
    static func grid(for size: CGSize, scale: CGFloat, cell: (width: Int, height: Int), padding: Int) -> TerminalSize {
        func count(_ points: CGFloat, _ cell: Int) -> UInt16 {
            // The same rounding as the drawable, so the grid never reaches beyond it.
            let pixels = Int((points * scale).rounded()) - 2 * padding
            return UInt16(min(max(1, pixels / cell), Int(Terminal.maximumGridDimension)))
        }
        return TerminalSize(columns: count(size.width, cell.width), rows: count(size.height, cell.height))
    }

    /// The size of a view in points that holds exactly `grid`: the opposite
    /// of `grid(for:scale:cell:padding:)`.
    static func size(holding grid: TerminalSize, scale: CGFloat, cell: (width: Int, height: Int), padding: Int) -> CGSize {
        CGSize(
            width: CGFloat(Int(grid.columns) * cell.width + 2 * padding) / scale,
            height: CGFloat(Int(grid.rows) * cell.height + 2 * padding) / scale
        )
    }
}
