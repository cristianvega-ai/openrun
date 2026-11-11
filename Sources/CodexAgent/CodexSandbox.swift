import AgentConversation

/// What the commands of a Codex thread may change on their own. Outside
/// it, Codex asks for approval first.
public enum CodexSandbox: String, Sendable, Hashable, CaseIterable {
    /// Commands read only. Codex asks before each change.
    case readOnly
    /// Commands may write in the folder of the thread.
    case workspaceWrite

    /// The value of `thread/start` and `thread/resume`.
    var threadValue: JSONValue {
        .string(self == .readOnly ? "read-only" : "workspace-write")
    }

    /// The value of `turn/start`.
    var turnValue: JSONValue {
        .object(["type": .string(rawValue)])
    }
}
