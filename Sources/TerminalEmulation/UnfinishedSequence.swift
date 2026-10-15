import GhosttyVt

/// The start of an escape sequence or a UTF-8 character that a terminal has
/// parsed and that the program has not finished yet.
///
/// A client that draws a picture of a restored snapshot writes these bytes
/// after the picture. The output that follows the snapshot then finishes the
/// sequence in the real terminal, as it does in the restored terminal.
/// Without them, the real terminal would show the end of the sequence as text.
public struct UnfinishedSequence: Equatable, Sendable {
    /// The bytes in the order the program wrote them. Empty when the terminal
    /// is between sequences.
    public let bytes: [UInt8]

    /// Reads the unfinished sequence of a terminal.
    ///
    /// libghostty-vt knows the bytes only when it tracked them from the first
    /// one. A new `Terminal` tracks from its start, and a restored terminal
    /// tracks from its snapshot on, so both can answer.
    public init(of terminal: Terminal) throws {
        var copied: UnsafeMutablePointer<UInt8>?
        var length = 0
        try TerminalEmulationError.check(
            ghostty_terminal_continuation_alloc(terminal.handle, nil, &copied, &length),
            from: "ghostty_terminal_continuation_alloc"
        )
        defer { ghostty_free(nil, copied, length) }
        guard let copied else {
            bytes = []
            return
        }
        bytes = Array(UnsafeBufferPointer(start: copied, count: length))
    }
}
