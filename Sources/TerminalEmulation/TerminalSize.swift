/// The size of a terminal grid in character cells.
public struct TerminalSize: Equatable, Hashable, Sendable {
    public var columns: UInt16
    public var rows: UInt16

    /// Both values must be greater than zero. libghostty-vt rejects an empty grid.
    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}
