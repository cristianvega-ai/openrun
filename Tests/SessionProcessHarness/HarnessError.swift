public enum HarnessError: Error, CustomStringConvertible {
    case processEnded(log: String)
    case socketNotReady(log: String)
    case commandFailed(description: String)

    public var description: String {
        switch self {
        case .processEnded(let log): "The session process ended before it listened. Log:\n\(log)"
        case .socketNotReady(let log): "The session process did not listen in time. Log:\n\(log)"
        case .commandFailed(let description): description
        }
    }
}
