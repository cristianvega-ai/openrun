/// Finds the JSON text of the member `id` of the object on a line, as the
/// app-server wrote it. The decoder of the line keeps a number only as a
/// `Double`, and the answer to a request must give it back exactly.
enum CodexIdentifierToken {
    static func find(in bytes: some Collection<UInt8>) -> String? {
        let bytes = Array(bytes)
        var index = 0
        var depth = 0
        var nextStringIsKey = false
        var keyIsIdentifier = false
        var valueIsNext = false
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                let start = index
                index = endOfString(bytes, from: index)
                if depth == 1, valueIsNext { return String(decoding: bytes[start..<index], as: UTF8.self) }
                if depth == 1, nextStringIsKey {
                    keyIsIdentifier = bytes[start..<index].elementsEqual("\"id\"".utf8)
                    nextStringIsKey = false
                }
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                if valueIsNext { return nil }
                depth += 1
                nextStringIsKey = depth == 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 1 { nextStringIsKey = true }
            case UInt8(ascii: ":"):
                if depth == 1, keyIsIdentifier { valueIsNext = true }
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                break
            default:
                guard depth == 1, valueIsNext else { break }
                let start = index
                while index < bytes.count, !Array(",}] \t\r\n".utf8).contains(bytes[index]) { index += 1 }
                return String(decoding: bytes[start..<index], as: UTF8.self)
            }
            index += 1
        }
        return nil
    }

    /// The index after the quote that ends the string at `start`.
    static func endOfString(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start + 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\") {
                index += 2
            } else if bytes[index] == UInt8(ascii: "\"") {
                return index + 1
            } else {
                index += 1
            }
        }
        return bytes.count
    }
}
