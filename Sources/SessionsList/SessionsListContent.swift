/// Everything that the second pane shows.
public struct SessionsListContent: Equatable, Sendable {
    /// The name of the entry of the first pane, such as "All Sessions" or a project.
    public var title: String
    /// The rows in the user's own order. The pane filters and orders them.
    public var rows: [SessionRowDisplay]
    /// The shown names of the agents that the new-session button offers.
    public var agents: [String]

    public init(title: String = "", rows: [SessionRowDisplay] = [], agents: [String] = []) {
        (self.title, self.rows, self.agents) = (title, rows, agents)
    }
}
