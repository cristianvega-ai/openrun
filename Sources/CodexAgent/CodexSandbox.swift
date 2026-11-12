import AgentConversation

/// What the commands of a Codex thread may change on their own. Outside
/// it, Codex asks for approval first.
public enum CodexSandbox: String, Sendable, Hashable, CaseIterable {
    /// Commands read only. Codex asks before each change.
    case readOnly
    /// Commands may write in the folder of the thread.
    case workspaceWrite

    /// The word of the sandbox for `codex --sandbox`.
    public var commandLineWord: String {
        self == .readOnly ? "read-only" : "workspace-write"
    }

    /// The value of `thread/start` and `thread/resume`.
    var threadValue: JSONValue {
        .string(commandLineWord)
    }

    /// The arguments of `codex` that go on with a thread in a terminal,
    /// where the user answers the questions of Codex (proposal 6).
    public func terminalArguments(thread: String, model: String?) -> [String] {
        ["resume", thread] + (model.map { ["--model", $0] } ?? []) + ["--sandbox", commandLineWord]
    }

    /// The value of `turn/start`.
    var turnValue: JSONValue {
        .object(["type": .string(rawValue)])
    }
}
