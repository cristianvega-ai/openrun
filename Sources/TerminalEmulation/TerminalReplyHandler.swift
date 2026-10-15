import Darwin
import GhosttyVt

/// Receives the bytes a terminal sends back to its program, such as the
/// answer to a cursor position query.
public typealias TerminalReplyHandler = (_ bytes: [UInt8]) -> Void

/// Holds the handler at a fixed address, so libghostty-vt can carry a plain
/// pointer to it. The terminal owns the box and frees it after the terminal.
final class TerminalReplyBox {
    let handler: TerminalReplyHandler

    init(handler: @escaping TerminalReplyHandler) {
        self.handler = handler
    }
}

extension Terminal {

    /// Installs the handler that receives the terminal's replies, or removes
    /// it when `handler` is `nil`.
    ///
    /// The terminal calls the handler while it parses output, on the thread
    /// that called `write`. The handler must not write to this terminal.
    ///
    public func setReplyHandler(
        _ handler: TerminalReplyHandler?,
    ) throws {
        guard let handler else {
            let previous = replyBox
            try installCallbacks(userdata: nil, enabled: false)
            replyBox = nil
            withExtendedLifetime(previous) {}
            return
        }
        try install(TerminalReplyBox(handler: handler))
    }

    /// Stores the box, then points libghostty-vt at it.
    ///
    /// The box must be stored first. If the install failed half way after a
    /// pointer was handed over, a box that nothing owns would leave
    /// libghostty-vt with a dangling pointer.
    /// - Parameter beforeInstalling: Runs between the two steps. Tests use it.
    func install(_ box: TerminalReplyBox, beforeInstalling: () -> Void = {}) throws {
        // The old box stays alive until libghostty-vt stopped using it.
        let previous = replyBox
        replyBox = box
        beforeInstalling()
        do {
            try installCallbacks(userdata: Unmanaged.passUnretained(box).toOpaque(), enabled: true)
        } catch {
            // Take the callbacks back. When that fails too, libghostty-vt may
            // still hold the pointer, so the box stays stored and alive.
            if (try? installCallbacks(userdata: nil, enabled: false)) != nil {
                replyBox = nil
            }
            withExtendedLifetime(previous) {}
            throw error
        }
        withExtendedLifetime(previous) {}
    }

    // MARK: - Private

    private static let replyWriteCallback: GhosttyTerminalWritePtyFn = { _, userdata, bytes, length in
        guard let userdata, let bytes, length > 0 else { return }
        let box = Unmanaged<TerminalReplyBox>.fromOpaque(userdata).takeUnretainedValue()
        box.handler(Array(UnsafeBufferPointer(start: bytes, count: length)))
    }

    /// Sets or clears every callback that answers a query.
    private func installCallbacks(userdata: UnsafeMutableRawPointer?, enabled: Bool) throws {
        // Clear the callbacks before the userdata changes, so none runs with
        // a pointer to a box that is gone.
        let callbacks: [(GhosttyTerminalOption, UnsafeRawPointer)] = [
            (GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(Self.replyWriteCallback, to: UnsafeRawPointer.self)),
        ]
        for (option, _) in callbacks {
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, nil), from: "ghostty_terminal_set")
        }
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_USERDATA, userdata),
            from: "ghostty_terminal_set"
        )
        guard enabled else { return }
        for (option, function) in callbacks {
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, function), from: "ghostty_terminal_set")
        }
    }
}
