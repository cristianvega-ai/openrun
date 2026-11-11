/// An account of an agent: a login to the user's subscription (decision
/// of 2026-11-10). OpenRun keeps only its name and where the agent keeps
/// its settings. It never reads the credentials in that folder.
public struct ThreadAccount: Codable, Equatable, Sendable {
    /// The name that the user gave the account.
    public var name: String
    /// The folder of the agent's settings, which selects the account:
    /// `CLAUDE_CONFIG_DIR` for Claude Code, `CODEX_HOME` for Codex.
    public var settingsFolder: String

    public init(name: String, settingsFolder: String) {
        (self.name, self.settingsFolder) = (name, settingsFolder)
    }
}
