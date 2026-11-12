/// Everything that the first pane shows: the projects in the user's order,
/// and the counts of rows that need the user. "All Projects" shows no count,
/// because "Needs You" under it shows the same number.
public struct ProjectsListContent: Equatable, Sendable {
    public var projects: [ProjectDisplay]
    /// The rows that need the user in every project, for "Needs You".
    public var needsYouCount: Int
    /// The usage of each account that gave a reading, for the foot of the pane.
    public var accounts: [AccountUsageDisplay]

    public init(projects: [ProjectDisplay] = [], needsYouCount: Int = 0, accounts: [AccountUsageDisplay] = []) {
        (self.projects, self.needsYouCount, self.accounts) = (projects, needsYouCount, accounts)
    }
}
