/// How a session's program ended.
public enum SessionExit: Codable, Equatable, Sendable, CustomStringConvertible {
    case exited(status: Int32)
    case signaled(signal: Int32)

    /// The number a shell reports: the status, or 128 plus the signal.
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
