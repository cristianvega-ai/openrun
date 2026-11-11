/// The environment of the process of a Claude Code thread.
public enum ClaudeCodeEnvironment {
    /// Variables that Claude Code sets for the programs that it starts.
    /// Claude Code treats a process that has them as a run inside another
    /// run, so they must not reach a thread, also when the session process
    /// itself started inside an agent.
    public static let nestedRunVariables: Set<String> = [
        "AI_AGENT", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_EXECPATH",
        "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_PID", "CLAUDE_EFFORT",
    ]

    /// The prefix of the variables of the messaging socket of a run.
    public static let nestedRunPrefix = "CLAUDE_CODE_MESSAGING_"

    /// The base environment, usually that of the user's login shell,
    /// without the variables of a nested run, and with `additions` on top.
    /// `CLAUDE_CONFIG_DIR` stays, because it selects the account.
    public static func make(base: [String: String], additions: [String: String] = [:]) -> [String: String] {
        var environment = base.filter { name, _ in
            !nestedRunVariables.contains(name) && !name.hasPrefix(nestedRunPrefix)
        }
        environment.merge(additions) { _, added in added }
        return environment
    }
}
