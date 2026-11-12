import AgentThreads
import Settings

/// The other accounts of each agent, from the settings
/// `claude-code-accounts` and `codex-accounts`. A thread that names no
/// account runs under the account of the login shell.
struct ThreadAccountChoices: Equatable {
    var accounts: [ThreadAgent: [ThreadAccount]] = [:]

    init() {}

    init(_ settings: SettingValues) {
        accounts = [
            .claudeCode: settings.claudeCodeAccounts.map { ThreadAccount(name: $0.name, settingsFolder: $0.settingsFolder) },
            .codex: settings.codexAccounts.map { ThreadAccount(name: $0.name, settingsFolder: $0.settingsFolder) },
        ]
    }

    /// The account of the agent with the name, whatever its case.
    func account(named name: String, of agent: ThreadAgent) -> ThreadAccount? {
        accounts[agent]?.first { $0.name.lowercased() == name.lowercased() }
    }
}
