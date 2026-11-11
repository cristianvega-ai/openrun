/// What a row of the second pane holds: a thread with an agent, or a plain
/// terminal session (proposals 1 and 12 of 2026-11-10). The row shows the
/// kind as an outline icon.
public enum SessionKind: Equatable, Sendable {
    /// A thread with an agent, with the agent's shown name, such as
    /// "Claude Code" or "Codex", and the names of its model and account
    /// when the host knows them.
    case agentThread(agent: String, model: String?, account: String?)
    case terminal
}
