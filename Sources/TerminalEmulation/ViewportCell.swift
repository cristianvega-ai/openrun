/// A cell of the viewport, counted from zero at the top left.
public struct ViewportCell: Equatable, Hashable, Sendable {
    public var column: UInt16
    public var row: UInt32

    public init(column: UInt16, row: UInt32) {
        self.column = column
        self.row = row
    }
}
