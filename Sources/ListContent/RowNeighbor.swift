import Foundation

/// The row that takes the selection when the selected row goes away, so
/// the third pane does not go empty while other rows remain.
public enum RowNeighbor {
    /// The row that came after `removed` in the list, or else the one
    /// before it, among the rows that remain.
    ///
    /// - Parameter rows: The rows of the list as it showed them, with `removed`.
    public static func of(_ removed: UUID, in rows: [UUID], remaining: Set<UUID>) -> UUID? {
        guard let index = rows.firstIndex(of: removed) else { return nil }
        return rows[(index + 1)...].first(where: remaining.contains) ?? rows[..<index].last(where: remaining.contains)
    }
}
