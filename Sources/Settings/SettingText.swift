/// The rules for text that a setting holds or that an error shows.
enum SettingText {
    /// Whether text has 1 to `lengthLimit` characters (or 0, when `empty`
    /// is allowed) and no control character or line break. Such characters
    /// in a name could change the lines around it where it shows.
    static func isPlain(_ text: String, lengthLimit: Int, allowsEmpty: Bool = false) -> Bool {
        guard (allowsEmpty || !text.isEmpty), text.count <= lengthLimit else { return false }
        return !text.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: true
            default: false
            }
        }
    }

    /// Text from a client, made safe to show in an error: at most 64
    /// characters, in quotes, with each control and format character, a
    /// quote and a backslash written as an escape. A format character, such
    /// as a direction override, can reorder what the user reads.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars.prefix(64) {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                result += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default:
                if scalar == "\"" || scalar == "\\" { result += "\\" }
                result.unicodeScalars.append(scalar)
            }
        }
        if text.unicodeScalars.count > 64 { result += "…" }
        return result + "\""
    }
}
