/// Makes text from an untrusted source safe to print.
///
/// A control character in a terminal or a log can move the cursor, forge a
/// line, change the title, or write to the clipboard. The session process
/// shows text that clients chose, such as a folder or an error message, so
/// everything printed passes through here.
public enum PrintableText {
    /// Returns the text with no control character left.
    ///
    /// A backslash becomes two backslashes, so the result is unambiguous. A
    /// tab, a new line and a carriage return become `\t`, `\n` and `\r`. Every
    /// other C0 control (U+0000 to U+001F), DEL (U+007F) and C1 control
    /// (U+0080 to U+009F) becomes `\u{XX}` in upper-case hexadecimal. All
    /// other text, including letters outside ASCII and emoji, stays as it is.
    public static func escaping(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x5C: result += "\\\\"
            case 0x09: result += "\\t"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x00...0x1F, 0x7F...0x9F:
                result += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
