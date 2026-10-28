import TerminalEmulation

/// An event in the order in which the session sent it.
enum TerminalOutputEvent {
    case bytes([UInt8])
    case size(TerminalSize, tellsDelegate: Bool)
}
