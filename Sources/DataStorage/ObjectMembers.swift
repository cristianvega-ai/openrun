import Foundation

/// The members of a JSON object, each with the exact text of its value.
///
/// A decoder turns a number into a Double and loses digits, such as those
/// of 18446744073709551615 or the sign of -0.0. A member that this build
/// does not know must go back into the file as it was, so it is kept as
/// its text and never decoded.
struct ObjectMembers {
    /// The text of each value, by its key.
    private(set) var values: [String: Data] = [:]

    /// Reads the members of the object that `data` holds, or gives `nil`
    /// when `data` is not one JSON object.
    init?(parsing data: Data) {
        var scanner = DocumentTextScanner(bytes: [UInt8](data))
        guard scanner.take(UInt8(ascii: "{")) else { return nil }
        if scanner.take(UInt8(ascii: "}")) {
            guard scanner.atEnd else { return nil }
            return
        }
        repeat {
            guard let keyText = scanner.string(),
                  let key = try? JSONDecoder().decode(String.self, from: Data(keyText)),
                  scanner.take(UInt8(ascii: ":")),
                  let value = scanner.value() else { return nil }
            values[key] = Data(value)
        } while scanner.take(UInt8(ascii: ","))
        guard scanner.take(UInt8(ascii: "}")), scanner.atEnd else { return nil }
    }

    subscript(key: String) -> Data? {
        get { values[key] }
        set { values[key] = newValue }
    }

    /// The object with its keys in order and one key on each line, as
    /// `JSONEncoder` writes it with `.prettyPrinted` and `.sortedKeys`.
    func rendered() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        var result = Data("{\n".utf8)
        for (index, key) in values.keys.sorted().enumerated() {
            result += Data("  ".utf8)
            result += (try? encoder.encode(key)) ?? Data()
            result += Data(" : ".utf8)
            result += values[key] ?? Data("null".utf8)
            result += Data((index == values.count - 1 ? "\n" : ",\n").utf8)
        }
        return result + Data("}\n".utf8)
    }
}
