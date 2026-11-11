import Foundation

/// The rules that keep the rows in step with the sessions that run.
extension WindowLayout {
    public func row(_ identifier: UUID) -> LayoutRow? {
        rows.first { $0.identifier == identifier }
    }

    /// The row that shows a session or a thread, if one does.
    public func row(showing identifier: UUID) -> LayoutRow? {
        rows.first { $0.pane.sessions.contains(identifier) || $0.pane.threads.contains(identifier) }
    }

    /// Brings the rows in step with the sessions that run, oldest first.
    ///
    /// A session that no row shows gets a row of its own at the top, so
    /// the newest session comes first. A session that ended leaves its
    /// row, and a row with no session goes away. A file that the user
    /// changed can name a row or a session twice, and only the first
    /// stays. The selected row stays selected only while it exists.
    ///
    /// - Parameter threads: The agent threads that exist, oldest first, or
    ///   `nil` while the app does not know them. The rows of the threads
    ///   then stay as they are.
    public mutating func follow(sessions running: [UUID], threads: [UUID]? = nil) {
        let known = rows.flatMap(\.pane.threads)
        let runs = Set(running + (threads ?? known))
        var shown = Set<UUID>(), identifiers = Set<UUID>()
        rows = rows.compactMap { row in
            guard !identifiers.contains(row.identifier),
                  let pane = row.pane.keeping({ runs.contains($0) && shown.insert($0).inserted }) else { return nil }
            identifiers.insert(row.identifier)
            return LayoutRow(identifier: row.identifier, pane: pane)
        }
        for session in running where !shown.contains(session) && !identifiers.contains(session) {
            rows.insert(LayoutRow(session: session), at: 0)
        }
        for thread in threads ?? [] where !shown.contains(thread) && !identifiers.contains(thread) {
            rows.insert(LayoutRow(thread: thread), at: 0)
        }
        if let selectedRow, row(selectedRow) == nil { self.selectedRow = nil }
    }

    /// Moves a row to `index` among `visible`, the rows that the list
    /// shows now, in the user's order. The list can show the rows of one
    /// project only. The rows that it does not show keep their places.
    public mutating func moveRow(_ identifier: UUID, toIndex index: Int, among visible: [UUID]) {
        guard let source = rows.firstIndex(where: { $0.identifier == identifier }) else { return }
        let row = rows.remove(at: source)
        let others = visible.filter { $0 != identifier }
        func place(of other: UUID) -> Int? { rows.firstIndex { $0.identifier == other } }
        if index < others.count, index >= 0, let before = place(of: others[index]) {
            rows.insert(row, at: before)
        } else if let last = others.last, let after = place(of: last) {
            rows.insert(row, at: after + 1)
        } else {
            rows.insert(row, at: min(source, rows.count))
        }
    }
}
