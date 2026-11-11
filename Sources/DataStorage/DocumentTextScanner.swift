/// Finds the bounds of the strings and values of JSON text, without a
/// decode. It checks only the bounds, so read text that a decoder has
/// already accepted.
struct DocumentTextScanner {
    let bytes: [UInt8]
    private var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var atEnd: Bool {
        mutating get {
            skipSpace()
            return position == bytes.count
        }
    }

    /// Takes `byte` when it comes next.
    mutating func take(_ byte: UInt8) -> Bool {
        skipSpace()
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    /// The text of the string that comes next, with its quotes.
    mutating func string() -> ArraySlice<UInt8>? {
        skipSpace()
        let start = position
        guard take(UInt8(ascii: "\"")) else { return nil }
        while position < bytes.count {
            let byte = bytes[position]
            position += byte == UInt8(ascii: "\\") ? 2 : 1
            if byte == UInt8(ascii: "\"") { return bytes[start..<position] }
        }
        return nil
    }

    /// The text of the value that comes next: a string, an object or an
    /// array with all that it holds, or a number, `true`, `false` or `null`.
    mutating func value() -> ArraySlice<UInt8>? {
        skipSpace()
        guard position < bytes.count else { return nil }
        let start = position
        switch bytes[position] {
        case UInt8(ascii: "\""):
            return string()
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while position < bytes.count {
                switch bytes[position] {
                case UInt8(ascii: "\""):
                    guard string() != nil else { return nil }
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
                default: break
                }
                position += 1
                if depth == 0 { return bytes[start..<position] }
            }
            return nil
        default:
            let ends: Set<UInt8> = [UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D]
            while position < bytes.count, !ends.contains(bytes[position]) { position += 1 }
            return position > start ? bytes[start..<position] : nil
        }
    }

    private mutating func skipSpace() {
        while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
    }
}
