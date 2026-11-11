/// Any JSON value in `settings.json`.
///
/// A file can hold a setting of a later build, which this build must keep
/// as it is when it saves the file again.
indirect enum StoredValue: Codable, Hashable, Sendable {
    case null
    case flag(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([StoredValue])
    case object([String: StoredValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let integer = try? container.decode(Int64.self) {
            // Before Double, so a large whole number keeps every digit.
            self = .integer(integer)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([StoredValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: StoredValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .flag(let flag): try container.encode(flag)
        case .integer(let integer): try container.encode(integer)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}
