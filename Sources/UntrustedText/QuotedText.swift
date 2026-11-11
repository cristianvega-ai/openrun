/// Text from a client or a file, made safe to put in a message that a
/// terminal or a log shows.
public enum QuotedText {
    /// The text in quotes, with each control and format character and each
    /// line or paragraph separator written as `\u{XX}`, and a quote and a
    /// backslash after a backslash. Text after `characterLimit` Unicode
    /// scalars is cut and ends with "…".
    ///
    /// A format character, such as a direction override, can reorder what
    /// the user reads, so it shows as its code too.
    public static func quoted(_ text: String, characterLimit: Int = 256) -> String {
        var result = "\""
        for scalar in text.unicodeScalars.prefix(characterLimit) {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                result += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default:
                if scalar == "\"" || scalar == "\\" { result += "\\" }
                result.unicodeScalars.append(scalar)
            }
        }
        if text.unicodeScalars.count > characterLimit { result += "…" }
        return result + "\""
    }
}
