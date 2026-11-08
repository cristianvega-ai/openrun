/// A program that edits a command line at the cursor, and that draws its
/// lines again after the terminal changes size.
public enum LineEditor: Sendable, Equatable {
    /// The zsh line editor. It answers a new size with a move up to its
    /// first line, an erase below the cursor (`CSI J`), and its lines.
    case zsh
    /// GNU Readline, as in bash. It answers a new size with an erase of its
    /// last row (`CR CSI K`), an erase of each row above it (`CSI A CSI K`),
    /// and the last line of its prompt with the input.
    case readline
}
