import Foundation
import GhosttyVt

/// One virtual terminal: it parses the bytes a program writes and keeps the
/// screen, the scrollback, and the cursor.
///
/// A `Terminal` is not thread-safe. Call it from one thread at a time.
/// It owns one libghostty-vt terminal and frees it when it is released.
public final class Terminal {
    let handle: GhosttyTerminal

    /// Creates an empty terminal.
    public convenience init(size: TerminalSize, scrollbackLimit: Int) throws {
        var created: GhosttyTerminal?
        try TerminalEmulationError.check(
            ghostty_terminal_new(nil, &created, size.columns, size.rows),
            from: "ghostty_terminal_new"
        )
        try self.init(adopting: created, scrollbackLimit: scrollbackLimit)
    }

    /// Takes ownership of a libghostty-vt terminal.
    init(adopting created: GhosttyTerminal?, scrollbackLimit: Int) throws {
        guard let created else {
            throw TerminalEmulationError(function: "ghostty_terminal_new", resultCode: GHOSTTY_INVALID_VALUE.rawValue)
        }
        handle = created
        // A throw from here runs deinit, which frees the terminal once.
        try configure(scrollbackLimit: scrollbackLimit)
    }

    deinit {
        ghostty_terminal_free(handle)
    }

    /// The grid size.
    public var size: TerminalSize {
        TerminalSize(
            columns: (try? value(GHOSTTY_TERMINAL_DATA_COLS, as: UInt16.self)) ?? 0,
            rows: (try? value(GHOSTTY_TERMINAL_DATA_ROWS, as: UInt16.self)) ?? 0
        )
    }

    // MARK: - Private

    private func configure(scrollbackLimit: Int) throws {
        // The default byte limit would hide the line limit, so remove it.
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, nil),
            from: "ghostty_terminal_set"
        )
        var lineLimit = scrollbackLimit
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lineLimit),
            from: "ghostty_terminal_set"
        )
    }

    private func value<Value>(_ data: GhosttyTerminalData, as type: Value.Type) throws -> Value {
        let storage = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { storage.deallocate() }
        try TerminalEmulationError.check(
            ghostty_terminal_get(handle, data, storage),
            from: "ghostty_terminal_get"
        )
        return storage.pointee
    }
}
