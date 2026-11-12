/// What the new-session button of the second pane asks the host to start.
public enum NewSessionRequest: Equatable, Sendable {
    /// A new thread with the agent of this shown name, under the account
    /// of this name. `nil` is the account of the login shell of the user.
    case thread(agent: String, account: String? = nil)
    /// A new terminal that runs the command of this shown name, such as
    /// "Claude Code", or the login shell for `nil`.
    case terminal(command: String?)
}
