/// A cursor location in the active screen, counted from zero at the top left.
public struct TerminalCursorPosition: Equatable, Hashable, Sendable {
    public var column: UInt16
    public var row: UInt16

    public init(column: UInt16, row: UInt16) {
        self.column = column
        self.row = row
    }
}
