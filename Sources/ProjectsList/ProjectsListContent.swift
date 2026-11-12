/// Everything that the first pane shows: the projects in the user's order,
/// and the counts of rows that need the user. "All Projects" shows no count,
/// because "Needs You" under it shows the same number.
public struct ProjectsListContent: Equatable, Sendable {
    public var projects: [ProjectDisplay]
    /// The rows that need the user in every project, for "Needs You".
    public var needsYouCount: Int
    public var noProjectAttentionCount: Int
    /// Whether a thread or a terminal is in a folder of no project. Only
    /// then does the pane show "Other Folders".
    public var showsOtherFolders: Bool
    /// The usage of each account that gave a reading, for the foot of the pane.
    public var accounts: [AccountUsageDisplay]

    public init(
        projects: [ProjectDisplay] = [], needsYouCount: Int = 0, noProjectAttentionCount: Int = 0, showsOtherFolders: Bool = false,
        accounts: [AccountUsageDisplay] = []
    ) {
        (self.projects, self.needsYouCount, self.noProjectAttentionCount, self.accounts) = (projects, needsYouCount, noProjectAttentionCount, accounts)
        self.showsOtherFolders = showsOtherFolders || noProjectAttentionCount > 0
    }
}
