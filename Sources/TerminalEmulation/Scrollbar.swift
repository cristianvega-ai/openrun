/// Where the visible rows sit in the scrollback.
public struct Scrollbar: Equatable, Sendable {
    /// All rows: the scrollback and the active screen.
    public var totalRows: UInt64
    /// The first visible row, counted from the top of the scrollback.
    public var firstVisibleRow: UInt64
    public var visibleRows: UInt64
}
