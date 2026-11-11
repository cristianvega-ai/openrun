/// The text of a path that the user drops into the composer, which an
/// agent reads as one path, in the quotes of a shell when it needs them.
enum DroppedPath {
    private static let plainCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@%=")

    static func text(of path: String) -> String {
        if !path.isEmpty, path.allSatisfy(plainCharacters.contains) { return path }
        guard path.unicodeScalars.contains(where: isControl) else {
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        // A line break in single quotes would break the message, so the
        // quotes that take escapes show it as `\n`.
        var text = "$'"
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\n": text += "\\n"
            case "\t": text += "\\t"
            case "\r": text += "\\r"
            case "'", "\\": text += "\\" + String(scalar)
            case _ where isControl(scalar):
                let hex = String(scalar.value, radix: 16)
                text += "\\x" + (hex.count < 2 ? "0" : "") + hex
            default: text.unicodeScalars.append(scalar)
            }
        }
        return text + "'"
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }
}
