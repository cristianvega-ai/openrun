import GhosttyVt

/// Text that the user pastes, encoded for the program.
///
/// A terminal cannot use `ghostty_terminal_paste`: it writes through the
/// write callback, and a client terminal must not install that callback
/// (see "Query replies" in `documentation/architecture.md`).
public struct PasteText: Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// The bytes for the program: wrapped for a bracketed paste when the
    /// program turned mode 2004 on, with line feeds as carriage returns
    /// otherwise, and with unsafe control bytes as spaces.
    public func encoded(for terminal: Terminal) throws -> [UInt8] {
        let bracketed = terminal.isModeEnabled(.bracketedPaste)
        var input = Array(text.utf8)
        // The wrapper adds 12 bytes, and the rest is never longer than the text.
        var output = [UInt8](repeating: 0, count: input.count + 12)
        var written = 0
        let result = input.withUnsafeMutableBytes { input in
            output.withUnsafeMutableBytes { output in
                ghostty_paste_encode(
                    input.baseAddress?.assumingMemoryBound(to: CChar.self), input.count, bracketed,
                    output.baseAddress?.assumingMemoryBound(to: CChar.self), output.count, &written
                )
            }
        }
        try TerminalEmulationError.check(result, from: "ghostty_paste_encode")
        return Array(output.prefix(written))
    }
}
