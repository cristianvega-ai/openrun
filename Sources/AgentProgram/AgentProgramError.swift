import Darwin

/// An agent program could not start, or could not take input.
public enum AgentProgramError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)
    /// No executable file with this name exists in the search path.
    case programNotFound(name: String)
    /// The program ended, or closed its standard input, before the input
    /// reached it.
    case programEnded
    /// A value of the launch would reach the program changed, so the program
    /// was not started. `problem` names the value and never repeats it,
    /// because the value can be a secret.
    case invalidLaunchValue(problem: String)

    public var description: String {
        switch self {
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        case .programNotFound(let name):
            "No program named \(name) was found in the search path."
        case .programEnded:
            "The program ended before it could take the input."
        case .invalidLaunchValue(let problem):
            "The program was not started: \(problem)."
        }
    }
}
