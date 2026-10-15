/// How `Terminal.formatted` writes the screen.
public enum ScreenFormat: Equatable, Sendable {
    /// Text only. Trailing blanks on each line are trimmed.
    case plainText
}
