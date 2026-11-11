/// Cells next to each other in one row of the viewport, such as the part of
/// a web address in that row.
public struct ViewportCellRun: Equatable, Sendable {
    /// The row from the top of the viewport.
    public let row: Int
    public let columns: Range<Int>

    public init(row: Int, columns: Range<Int>) {
        (self.row, self.columns) = (row, columns)
    }
}
