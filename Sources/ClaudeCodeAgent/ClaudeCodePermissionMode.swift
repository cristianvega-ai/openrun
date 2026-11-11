/// The permission modes that OpenRun gives Claude Code.
///
/// The mode that skips every check, `bypassPermissions`, is left out on
/// purpose: OpenRun never starts an agent in it.
public enum ClaudeCodePermissionMode: String, Codable, Sendable, CaseIterable {
    /// Claude Code asks before edits and commands that no rule allows.
    case standard = "default"
    /// Edits and file commands in the working folders run without a question.
    case acceptEdits
    /// The agent only reads and plans.
    case plan
    /// Anything that would ask is denied.
    case doNotAsk = "dontAsk"
    /// A classifier of Claude Code decides instead of the user.
    case automatic = "auto"

    /// The modes from the strictest to the widest: each one lets the
    /// agent do more without an answer of the user than the one before.
    public static let fromStrictestToWidest: [ClaudeCodePermissionMode] = [.plan, .doNotAsk, .standard, .acceptEdits, .automatic]

    /// The modes that let the agent do no more than `limit` does, the
    /// strictest first. A thread can take each of them (proposal 9).
    public static func modes(upTo limit: ClaudeCodePermissionMode) -> [ClaudeCodePermissionMode] {
        fromStrictestToWidest.prefix { $0 != limit } + [limit]
    }
}
