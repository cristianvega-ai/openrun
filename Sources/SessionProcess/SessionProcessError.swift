import Darwin

/// The session process could not start.
public enum SessionProcessError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Another session process already answers on this socket.
    case alreadyRunning(path: String)
    /// The lock file next to the socket was removed or replaced each
    /// time the session process took the lock.
    case lockFileKeepsChanging(path: String)
    /// What sits at the path of the lock file is not a regular file, such as
    /// a symbolic link, a named pipe or a folder.
    case lockFileIsNotARegularFile(path: String)
    /// The lock file belongs to another user, who could hold the lock and
    /// keep every session process from starting.
    case lockFileOfAnotherUser(path: String, owner: uid_t)
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)

    public var description: String {
        switch self {
        case .alreadyRunning(let path):
            "A session process already runs on \(path). Stop it first, or choose another socket with --socket."
        case .lockFileKeepsChanging(let path):
            "The lock file \(path) was replaced each time the session process took it. Check what changes files in that folder."
        case .lockFileIsNotARegularFile(let path):
            "The lock file \(path) is not a regular file, so the session process cannot use it. Remove it, or choose another socket with --socket."
        case .lockFileOfAnotherUser(let path, let owner):
            "The lock file \(path) belongs to another user (user \(owner)), who could keep the session process from starting. Remove it, or choose another socket with --socket."
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        }
    }

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> SessionProcessError {
        .systemCallFailed(function: function, code: errno)
    }
}
