import GhosttyVt

/// The complete state of a terminal as bytes: the screens, the scrollback,
/// the cursor, the modes, and any unfinished escape sequence or UTF-8
/// character.
///
/// A session process takes a snapshot at any point in the output. A client
/// restores it and then writes the bytes that follow. The restored terminal
/// ends in the same state as a terminal that received every byte, even when
/// the snapshot fell inside a sequence.
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

    /// Captures the state of a terminal in at most `byteLimit` bytes.
    ///
    /// A larger state loses its oldest lines of scrollback until it fits,
    /// and keeps as many lines as fit. The screens, the cursor, the modes and
    /// an unfinished sequence stay whole, so the bytes that follow the
    /// snapshot still continue it. The terminal itself keeps its scrollback,
    /// because the lines go from a copy of it.
    ///
    /// - Returns: `nil` when the state does not fit even without scrollback.
    public init?(capturing terminal: Terminal, byteLimit: Int) throws {
        var snapshot = try TerminalSnapshot(capturing: terminal)
        guard snapshot.bytes.count > byteLimit else {
            self = snapshot
            return
        }
        let (copy, scrollbackLines) = try snapshot.decode(scrollbackLimit: Terminal.maximumScrollbackLines)
        var lineLimit = scrollbackLines
        while snapshot.bytes.count > byteLimit {
            guard lineLimit > 0 else { return nil }
            // Lines of scrollback cost about the same, so the share of the
            // lines that fit is near the share of the bytes. The screens make
            // that guess too high, so the loop goes on with fewer lines.
            lineLimit = min(lineLimit - 1, lineLimit * max(byteLimit, 0) / snapshot.bytes.count)
            // libghostty-vt drops the oldest whole pages over the new limit.
            try TerminalEmulationError.check(
                ghostty_terminal_set(copy.handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lineLimit),
                from: "ghostty_terminal_set"
            )
            snapshot = try TerminalSnapshot(capturing: copy)
        }
        self = snapshot
    }

    /// Creates a terminal in the captured state.
    ///
    /// - Parameter scrollbackLimit: The most lines of scrollback to keep after
    ///   the restore. A snapshot does not carry this setting.
    public func restoreTerminal(scrollbackLimit: Int) throws -> Terminal {
        try decode(scrollbackLimit: scrollbackLimit).terminal
    }

    /// Restores the terminal, and counts the lines of scrollback of its
    /// primary screen in the snapshot. Without a count from libghostty-vt,
    /// the count is the most that a terminal holds, so a fit starts high.
    private func decode(scrollbackLimit: Int) throws -> (terminal: Terminal, scrollbackLines: Int) {
        try bytes.withUnsafeBufferPointer { buffer in
            var decoder: GhosttySnapshotDecoder?
            try TerminalEmulationError.check(
                ghostty_snapshot_decoder_new_buf(nil, &decoder, buffer.baseAddress, buffer.count),
                from: "ghostty_snapshot_decoder_new_buf"
            )
            defer { ghostty_snapshot_decoder_free(decoder) }

            // Keep tracking the unfinished sequence, so the restored terminal
            // can take its own snapshot before the next sequence ends.
            var continuationLimit = Terminal.continuationByteLimit
            try TerminalEmulationError.check(
                ghostty_snapshot_decoder_set(decoder, GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_CONTINUATION_BYTES, &continuationLimit),
                from: "ghostty_snapshot_decoder_set"
            )
            var retainContinuation = true
            try TerminalEmulationError.check(
                ghostty_snapshot_decoder_set(decoder, GHOSTTY_SNAPSHOT_DECODER_OPT_RETAIN_CONTINUATION, &retainContinuation),
                from: "ghostty_snapshot_decoder_set"
            )

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
