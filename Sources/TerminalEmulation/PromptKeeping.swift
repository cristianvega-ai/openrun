/// What a copy of the screen keeps of a shell's prompt when it takes a new
/// width. The session process decides, and each client that follows its
/// size does the same (see `ServerMessage.sizeChanged`).
public enum PromptKeeping: Sendable, Equatable {
    /// The text reflows, as for any output.
    case nothing
    /// The shell has erased its lines at the cursor. A cursor at the start
    /// of a blank row keeps a row of its own.
    case cursorRow
}
