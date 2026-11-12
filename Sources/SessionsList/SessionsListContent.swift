/// Everything that the second pane shows.
public struct SessionsListContent: Equatable, Sendable {
    /// The name of the entry of the first pane, such as "All Sessions" or a project.
    public var title: String
    /// The rows in the user's own order. The pane filters and orders them.
    public var rows: [SessionRowDisplay]
    /// The shown names of the agents that the new-session button offers.
    public var agents: [String]
    /// The names of the other accounts of an agent, by its shown name,
    /// from the settings. The button offers a thread under each one.
    public var accounts: [String: [String]]
    /// The shown names of the commands that a new terminal can run in
    /// place of the login shell, from the settings.
    public var terminalCommands: [String]

    public init(
        title: String = "", rows: [SessionRowDisplay] = [], agents: [String] = [], accounts: [String: [String]] = [:], terminalCommands: [String] = []
    ) {
        (self.title, self.rows, self.agents, self.accounts, self.terminalCommands) = (title, rows, agents, accounts, terminalCommands)
    }
}
