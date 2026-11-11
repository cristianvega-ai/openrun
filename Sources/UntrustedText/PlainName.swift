/// The rule for a name that a client or a file gives and that OpenRun
/// shows, in the app's lists or in a terminal: a project name, a theme or
/// font name, or a command of the new-session button.
public enum PlainName {
    /// Whether `text` has 1 to `lengthLimit` characters (or 0, when
    /// `allowsEmpty`), with no control character, no line or paragraph
    /// separator, and no character that changes the direction of text.
    ///
    /// A control character can move the cursor or change the title of a
    /// terminal, and a line break can forge a line. A direction override
    /// can make the text read as other text. Other format characters stay,
    /// such as the zero-width joiner that emoji need.
    public static func isValid(_ text: String, lengthLimit: Int, allowsEmpty: Bool = false) -> Bool {
        guard allowsEmpty || !text.isEmpty, text.count <= lengthLimit else { return false }
        return !text.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return true
            default: return changesDirection(scalar)
            }
        }
    }

    /// The embeddings and overrides U+202A to U+202E, the isolates U+2066
    /// to U+2069, and the marks U+200E, U+200F and U+061C.
    static func changesDirection(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069, 0x200E, 0x200F, 0x061C: true
        default: false
        }
    }
}
