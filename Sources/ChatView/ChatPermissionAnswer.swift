/// The user's answer to a permission request of the agent.
public enum ChatPermissionAnswer: Equatable, Hashable, Sendable {
    case allow
    /// The message, when there is one, goes to the agent with the denial,
    /// such as "Run the tests first".
    case deny(message: String?)
}
