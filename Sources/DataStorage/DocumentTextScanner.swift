/// Finds the bounds of the strings and values of JSON text, without a
/// decode, and accepts only strict JSON (RFC 8259).
///
/// Foundation's decoder also takes text that is not JSON, such as a raw
/// tab in a string, the escape `\q` or the number `01`. A value that this build keeps as
/// text goes back into the file, so it must be valid there. The scanner
/// does not check UTF-8; `ObjectMembers` checks the whole text.
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
            position += 1
            if byte == UInt8(ascii: "\"") { return bytes[start..<position] }
            if byte < 0x20 { return nil }
            if byte == UInt8(ascii: "\\"), !takeEscape() { return nil }
        }
        return nil
    }

    /// The rest of an escape after its backslash: one of `"\/bfnrt`, or
    /// `u` and four hexadecimal digits.
    private mutating func takeEscape() -> Bool {
        guard position < bytes.count else { return false }
        let escaped = bytes[position]
        position += 1
        guard escaped == UInt8(ascii: "u") else { return Array(#""\/bfnrt"#.utf8).contains(escaped) }
        for _ in 0..<4 {
            guard position < bytes.count, Self.hexadecimalDigits.contains(bytes[position]) else { return false }
            position += 1
        }
        return true
    }

    private static let hexadecimalDigits = Set("0123456789abcdefABCDEF".utf8)

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
        case UInt8(ascii: "t"): return takeWord("true") ? bytes[start..<position] : nil
        case UInt8(ascii: "f"): return takeWord("false") ? bytes[start..<position] : nil
        case UInt8(ascii: "n"): return takeWord("null") ? bytes[start..<position] : nil
        default: return takeNumber() ? bytes[start..<position] : nil
        }
    }

    private mutating func takeWord(_ word: String) -> Bool {
        let expected = Array(word.utf8)
        guard bytes[position...].starts(with: expected) else { return false }
        position += expected.count
        return true
    }

    /// `-`, then `0` or a digit 1 to 9 with more digits, then a fraction
    /// and an exponent that each can be left out. So `01`, `.5`, `+1` and
    /// `1.` fail.
    private mutating func takeNumber() -> Bool {
        if next(is: "-") { position += 1 }
        if next(is: "0") {
            position += 1
        } else if takeDigits() == 0 {
            return false
        }
        if next(is: ".") {
            position += 1
            guard takeDigits() > 0 else { return false }
        }
        if next(is: "e") || next(is: "E") {
            position += 1
            if next(is: "+") || next(is: "-") { position += 1 }
            guard takeDigits() > 0 else { return false }
        }
        return true
    }

    private mutating func takeDigits() -> Int {
        let start = position
        while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) { position += 1 }
        return position - start
    }

    private func next(is character: Unicode.Scalar) -> Bool {
        position < bytes.count && bytes[position] == UInt8(ascii: character)
    }

    private mutating func skipSpace() {
        while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
    }
}
