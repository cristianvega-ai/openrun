import Darwin

/// The session process could not start.
public enum SessionProcessError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Another session process already answers on this socket.
    case alreadyRunning(path: String)
    /// The lock file next to the socket was removed or replaced each
    /// time the session process took the lock.
    case lockFileKeepsChanging(path: String)
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)

    public var description: String {
        switch self {
        case .alreadyRunning(let path):
            "A session process already runs on \(path). Stop it first, or choose another socket with --socket."
        case .lockFileKeepsChanging(let path):
            "The lock file \(path) was replaced each time the session process took it. Check what changes files in that folder."
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        }
    }

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> SessionProcessError {
        .systemCallFailed(function: function, code: errno)
    }
}
