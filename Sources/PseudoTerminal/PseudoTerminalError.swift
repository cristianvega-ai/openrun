import Darwin

/// A pseudo terminal could not start a program or complete a request.
public enum PseudoTerminalError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)
    /// No executable file with this name exists in the search path.
    case programNotFound(name: String)
    /// The program ended, or closed its terminal, before input could reach it.
    case programEnded

    public var description: String {
        switch self {
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        case .programNotFound(let name):
            "No program named \(name) was found in the search path."
        case .programEnded:
            "The program ended before it could take the input."
        }
    }

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> PseudoTerminalError {
        .systemCallFailed(function: function, code: errno)
    }
}
