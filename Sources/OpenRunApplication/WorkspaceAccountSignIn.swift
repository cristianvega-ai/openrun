import ListContent

/// Sign In of the Accounts pane (decision of 2026-11-13).
extension Workspace {
    /// Starts the login of an agent in a new terminal of the main window,
    /// under the folder of the account, and shows that terminal.
    ///
    /// - Parameter account: The name of an account of the settings, or
    ///   `nil` for the login of the shell.
    func signIn(agent: String, account: String?) {
        let accounts = agent == "codex" ? settings.codexAccounts : agent == "claude-code" ? settings.claudeCodeAccounts : []
        let folder = account.flatMap { name in accounts.first { $0.name == name }?.settingsFolder }
        // An account that the session process does not hold yet has no folder for the login.
        guard account == nil || folder != nil else { return }
        // The session process keeps no program of Codex in the settings, and it starts `codex` too.
        let program = agent == "codex" ? "codex" : settings.claudeCodeProgram
        guard let commandLine = AccountSignIn(agent: agent, program: program, folder: folder).commandLine else { return }
        newSession(commandLine: commandLine, rowName: "Sign In to " + ThreadRowFacts.agentName(agent) + (account.map { " · \($0)" } ?? ""))
        window.window.makeKeyAndOrderFront(nil)
    }
}
