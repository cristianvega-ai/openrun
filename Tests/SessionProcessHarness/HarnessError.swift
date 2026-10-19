public enum HarnessError: Error, CustomStringConvertible {
    case commandFailed(description: String)

    public var description: String {
        switch self {
        case .commandFailed(let description): description
        }
    }
}
