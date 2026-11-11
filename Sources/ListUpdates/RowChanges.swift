import AppKit

/// The changes that turn one version of a list into the next, so a table
/// updates only the rows that changed. A list of 100 sessions gets frequent
/// updates of single rows, and a reload of the whole table for each one
/// would lose the selection, the scroll position and an edit in progress.
public struct RowChanges: Equatable, Sendable {
    /// The rows that go away, as indexes of the old list.
    public let removed: IndexSet
    /// The rows that come, as indexes of the new list. A row that moves goes
    /// away from its old place and comes at its new place.
    public let inserted: IndexSet
    /// The rows that stay and show new values, as indexes of the new list.
    public let changed: IndexSet

    /// - Parameter identifier: What stays the same for a row while its values change.
    public init<Row: Equatable, Identifier: Hashable>(from old: [Row], to new: [Row], identifier: (Row) -> Identifier) {
        let difference = new.map(identifier).difference(from: old.map(identifier))
        var removed = IndexSet(), inserted = IndexSet()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var oldRows: [Identifier: Row] = [:]
        for row in old { oldRows[identifier(row)] = oldRows[identifier(row)] ?? row }
        var changed = IndexSet()
        for (index, row) in new.enumerated() where !inserted.contains(index) {
            if oldRows[identifier(row)] != row { changed.insert(index) }
        }
        (self.removed, self.inserted, self.changed) = (removed, inserted, changed)
    }

    public var isEmpty: Bool { removed.isEmpty && inserted.isEmpty && changed.isEmpty }

    /// Removes and inserts the rows in one animated update, and then lets
    /// `updateRow` give each changed row that has a view its new values in place.
    @MainActor
    public func apply(to table: NSTableView, animation: NSTableView.AnimationOptions = [.effectFade], updateRow: (Int) -> Void) {
        if !removed.isEmpty || !inserted.isEmpty {
            table.beginUpdates()
            table.removeRows(at: removed, withAnimation: animation)
            table.insertRows(at: inserted, withAnimation: animation)
            table.endUpdates()
        }
        for index in changed where index < table.numberOfRows { updateRow(index) }
    }
}
