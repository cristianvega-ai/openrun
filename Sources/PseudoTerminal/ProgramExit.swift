/// How a program in a pseudo terminal ended.
public enum ProgramExit: Equatable, Sendable, CustomStringConvertible {
    /// The program called exit with this status.
    case exited(status: Int32)
    /// A signal ended the program.
    case signaled(signal: Int32)

    /// Decodes the status word that `waitpid` returns.
    init(waitStatus: Int32) {
        // The macros WIFEXITED and WTERMSIG are not available to Swift, so
        // this reads the same bit fields by hand.
        let signal = waitStatus & 0x7f
        if signal == 0 {
            self = .exited(status: (waitStatus >> 8) & 0xff)
        } else {
            self = .signaled(signal: signal)
        }
    }

    /// The number a shell reports for this exit: the status, or 128 plus the
    /// signal number.
    public var shellStatus: Int32 {
        switch self {
        case .exited(let status): status
        case .signaled(let signal): 128 + signal
        }
    }

    public var description: String {
        switch self {
        case .exited(let status): "exited with status \(status)"
        case .signaled(let signal): "ended by signal \(signal)"
        }
    }
}
