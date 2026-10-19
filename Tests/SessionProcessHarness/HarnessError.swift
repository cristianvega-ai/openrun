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

extension HarnessError {
    static func commandFailed(arguments: [String], result: CommandResult) -> HarnessError {
        .commandFailed(description: "openrun \(arguments.joined(separator: " ")) exited with \(result.status): \(result.standardError)")
    }
}
