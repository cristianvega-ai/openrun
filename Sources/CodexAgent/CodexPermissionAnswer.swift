/// The user's answer to a request of Codex to run a command or to change
/// files.
public enum CodexPermissionAnswer: String, Sendable, Hashable {
    case allow
    case deny

    /// The decision that goes to Codex.
    var decision: String {
        self == .allow ? "accept" : "decline"
    }
}
