import TerminalEmulation

/// An event in the order in which the session sent it.
enum TerminalOutputEvent {
    case bytes([UInt8])
    /// See `Terminal.resize(to:keepingCursorAtLineStart:)` for the last field.
    case size(TerminalSize, tellsDelegate: Bool, keepsCursorAtLineStart: Bool = false)
}
