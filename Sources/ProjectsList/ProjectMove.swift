/// A drag of one project to another place among the projects. The fixed
/// entries stay at the top and the bottom, so a drop lands only between
/// projects.
struct ProjectMove: Equatable {
    /// The index of the project among the projects, before the move.
    var source: Int
    /// The index of the project among the projects, after the move.
    var destination: Int

    /// - Parameters:
    ///   - row: The table row of the dragged project.
    ///   - dropRow: The table row above which the user drops it.
    ///   - projectCount: The number of projects. They start at `ProjectsListRow.firstProjectRow`.
    /// - Returns: `nil` when the row is no project or the move changes nothing.
    init?(row: Int, dropRow: Int, projectCount: Int) {
        let first = ProjectsListRow.firstProjectRow
        guard (first..<first + projectCount).contains(row) else { return nil }
        let above = min(max(dropRow, first), first + projectCount) - first
        let source = row - first
        let destination = above > source ? above - 1 : above
        guard destination != source else { return nil }
        (self.source, self.destination) = (source, destination)
    }

    /// The table row where the project lands.
    var destinationRow: Int { destination + ProjectsListRow.firstProjectRow }
}
