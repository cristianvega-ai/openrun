/// A launch of Claude Code that OpenRun refuses before anything starts.
public enum ClaudeCodeLaunchError: Error, Equatable, CustomStringConvertible {
    case invalidModel

    public var description: String {
        switch self {
        case .invalidModel: "The model name is empty, starts with a dash, or holds a character that no model name has."
        }
    }
}
