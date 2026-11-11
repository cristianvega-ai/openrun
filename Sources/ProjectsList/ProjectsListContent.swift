/// Everything that the first pane shows: the projects in the user's order,
/// and the counts of rows that need the user. "All Sessions" shows no count,
/// because "Needs You" under it shows the same number.
public struct ProjectsListContent: Equatable, Sendable {
    public var projects: [ProjectDisplay]
    /// The rows that need the user in every project, for "Needs You".
    public var needsYouCount: Int
    public var noProjectAttentionCount: Int

    public init(projects: [ProjectDisplay] = [], needsYouCount: Int = 0, noProjectAttentionCount: Int = 0) {
        (self.projects, self.needsYouCount, self.noProjectAttentionCount) = (projects, needsYouCount, noProjectAttentionCount)
    }
}
