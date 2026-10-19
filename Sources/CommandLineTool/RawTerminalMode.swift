import Darwin
import SessionProtocol
import Synchronization

/// Puts a terminal in raw mode: no echo, no line editing, no signals from
/// keys. Every key reaches the program in the session unchanged, and the
/// session's own terminal does the echo and the line editing.
///
/// Neither switch discards the keys that the user typed ahead. The next
/// reader of the terminal gets them: the session when raw mode starts, the
/// shell when it ends.
final class RawTerminalMode: Sendable {
    private let descriptor: Int32
    /// The mode to put back, while raw mode is on.
    private let original = Mutex<termios?>(nil)

    /// Saves the current mode and switches to raw mode.
    init(descriptor: Int32) throws {
        self.descriptor = descriptor
        try enter()
    }

    /// Saves the current mode and switches to raw mode, unless raw mode is on.
    /// After a suspension the user may have changed the mode, so the mode to
    /// put back is read again.
    func enter() throws {
        try original.withLock { original in
            guard original == nil else { return }
            var saved = termios()
            guard tcgetattr(descriptor, &saved) == 0 else {
                throw CommandLineToolError.failure("The terminal mode cannot be read: \(String(cString: strerror(errno))).")
            }
            var raw = saved
            cfmakeraw(&raw)
            // TCSANOW keeps the keys typed ahead, and it does not wait for
            // output, which a terminal that takes no output would never drain.
            guard tcsetattr(descriptor, TCSANOW, &raw) == 0 else {
                throw CommandLineToolError.failure("The terminal mode cannot be changed: \(String(cString: strerror(errno))).")
            }
            original = saved
        }
    }

    /// Puts the saved mode back. Safe to call again: only the first call
    /// after `enter` acts.
    ///
    /// TCSADRAIN lets the last output reach the terminal in raw mode and keeps
    /// the keys typed ahead. It waits until the output drains, which never
    /// happens while the terminal takes no output, such as a frozen `ssh`.
    /// So the restore waits at most `limit` for the output, and then
    /// switches at once with TCSANOW, which keeps the keys as well.
    func restore(waitingForOutputAtMost limit: Duration = .milliseconds(200)) {
        let saved = original.withLock { value -> termios? in
            defer { value = nil }
            return value
        }
        guard var saved else { return }
        tcsetattr(descriptor, outputDrains(within: limit) ? TCSADRAIN : TCSANOW, &saved)
        // Back in line editing, the kernel marks the keys typed ahead for
        // another pass (PENDIN), and the mode shows the mark until something
        // looks at the input. A poll looks at it now, so the mode reads as it
        // was before attaching. TCSAFLUSH would avoid the mark only by
        // discarding the keys.
        var input = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        _ = poll(&input, 1, 0)
    }

    private func outputDrains(within limit: Duration) -> Bool {
        let deadline = ContinuousClock.now + limit
        while true {
            var waiting: Int32 = 0
            guard ioctl(descriptor, TIOCOUTQ, &waiting) == 0 else { return false }
            if waiting == 0 { return true }
            if ContinuousClock.now >= deadline { return false }
            usleep(2_000)
        }
    }

    /// The size of the terminal on a descriptor, or `nil` when it is not a
    /// terminal.
    static func windowSize(of descriptor: Int32) -> SessionSize? {
        var size = winsize()
        guard ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return nil }
        return SessionSize(columns: size.ws_col, rows: size.ws_row)
    }
}
