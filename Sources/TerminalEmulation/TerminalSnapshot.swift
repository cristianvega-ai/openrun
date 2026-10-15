import GhosttyVt

public struct TerminalSnapshot: Equatable, Sendable {
    /// The encoded state. libghostty-vt does not yet promise to read bytes
    /// from another version, so keep them only for the same OpenRun build.
    public let bytes: [UInt8]

    /// Wraps bytes that an earlier snapshot produced.
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Captures the state of a terminal.
    public init(capturing terminal: Terminal) throws {
        var encoded: UnsafeMutablePointer<UInt8>?
        var length = 0
        try TerminalEmulationError.check(
            ghostty_snapshot_encode_alloc(terminal.handle, nil, &encoded, &length),
            from: "ghostty_snapshot_encode_alloc"
        )
        defer { ghostty_free(nil, encoded, length) }
        guard let encoded else {
            throw TerminalEmulationError(function: "ghostty_snapshot_encode_alloc", resultCode: GHOSTTY_NO_VALUE.rawValue)
        }
        bytes = Array(UnsafeBufferPointer(start: encoded, count: length))
    }

    /// Creates a terminal in the captured state.
    ///
    /// - Parameter scrollbackLimit: The most lines of scrollback to keep after
    ///   the restore. A snapshot does not carry this setting.
    public func restoreTerminal(scrollbackLimit: Int) throws -> Terminal {
        try decode(scrollbackLimit: scrollbackLimit).terminal
    }

    private func decode(scrollbackLimit: Int) throws -> (terminal: Terminal, scrollbackLines: Int) {
        try bytes.withUnsafeBufferPointer { buffer in
            var decoder: GhosttySnapshotDecoder?
            try TerminalEmulationError.check(
                ghostty_snapshot_decoder_new_buf(nil, &decoder, buffer.baseAddress, buffer.count),
                from: "ghostty_snapshot_decoder_new_buf"
            )
            defer { ghostty_snapshot_decoder_free(decoder) }


            var restored: GhosttyTerminal?
            try TerminalEmulationError.check(
                ghostty_snapshot_decoder_decode(decoder, &restored),
                from: "ghostty_snapshot_decoder_decode"
            )
            let terminal = try Terminal(adopting: restored, scrollbackLimit: scrollbackLimit)
            var scrollbackLines = UInt64(Terminal.maximumScrollbackLines)
            _ = ghostty_snapshot_decoder_get(decoder, GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_PRIMARY, &scrollbackLines)
            return (terminal, Int(min(scrollbackLines, UInt64(Terminal.maximumScrollbackLines))))
        }
    }
}
