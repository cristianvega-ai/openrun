/// What the new-session button of the second pane asks the host to start.
public enum NewSessionRequest: Equatable, Sendable {
    /// A new thread with the agent of this shown name.
    case thread(agent: String)
    case terminal
}
