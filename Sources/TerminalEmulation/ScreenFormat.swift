/// How `Terminal.formatted` writes the screen.
public enum ScreenFormat: Equatable, Sendable {
    /// Text only. Trailing blanks on each line are trimmed.
    case plainText
    /// Text with the sequences that restore styles, colors, the cursor,
    /// modes, and tab stops. Writing this output into a fresh terminal of the
    /// same size reproduces the screen.
    case virtualTerminalSequences
    /// Styled markup for display in a browser.
    case hypertextMarkup
}
