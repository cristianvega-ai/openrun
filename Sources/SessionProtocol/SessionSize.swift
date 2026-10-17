/// The size of a session's terminal in character cells.
public struct SessionSize: Codable, Equatable, Hashable, Sendable {
    public var columns: UInt16
    public var rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}
