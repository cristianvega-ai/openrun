import Darwin

/// The session process could not start.
public enum SessionProcessError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)

    public var description: String {
        switch self {
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        }
    }

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> SessionProcessError {
        .systemCallFailed(function: function, code: errno)
    }
}
