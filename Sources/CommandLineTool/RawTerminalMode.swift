import Darwin
import SessionProtocol
import Synchronization

final class RawTerminalMode: Sendable {

    /// The size of the terminal on a descriptor, or `nil` when it is not a
    /// terminal.
    static func windowSize(of descriptor: Int32) -> SessionSize? {
        var size = winsize()
        guard ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return nil }
        return SessionSize(columns: size.ws_col, rows: size.ws_row)
    }
}
