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
}
