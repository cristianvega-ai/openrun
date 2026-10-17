/// The size of a session's terminal in character cells.
public struct SessionSize: Codable, Equatable, Hashable, Sendable {
    public var columns: UInt16
    public var rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey {
        case columns
        case rows
    }

    // The decoder reports a number that does not fit a UInt16, such as 999999
    // or -1, without the path of its field. This check gives the path, so the
    // failure that a client gets can name the field.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try Self.cellCount(for: .columns, in: container)
        rows = try Self.cellCount(for: .rows, in: container)
    }

    private static func cellCount(for key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> UInt16 {
        let value = try container.decode(Int.self, forKey: key)
        guard let count = UInt16(exactly: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A size is 0 to 65,535 cells.")
        }
        return count
    }
}
