/// The agent of a thread. Users choose their agents, so this type can
/// grow (principle of 2026-10-11).
public enum ThreadAgent: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex = "codex"

    /// The name of the agent as the app and the tool show it.
    public var shownName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}
