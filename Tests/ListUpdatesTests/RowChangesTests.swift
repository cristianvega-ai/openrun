import AppKit
import Testing
@testable import ListUpdates

@MainActor @Suite struct RowChangesTests {
    private struct Row: Equatable {
        var identifier: Int
        var title: String
    }

    private func rows(_ identifiers: [Int], title: String = "") -> [Row] { identifiers.map { Row(identifier: $0, title: title) } }

    @Test func aNewValueOfOneRowChangesOnlyThatRow() {
        var new = rows(Array(0..<100))
        new[42].title = "changed"
        let changes = RowChanges(from: rows(Array(0..<100)), to: new) { $0.identifier }
        #expect(changes.removed.isEmpty && changes.inserted.isEmpty && changes.changed == IndexSet(integer: 42))
    }

    @Test func rowsThatComeAndGoAreInsertedAndRemoved() {
        let changes = RowChanges(from: rows([1, 2, 3, 4]), to: rows([1, 3, 4, 5])) { $0.identifier }
        #expect(changes.removed == IndexSet(integer: 1) && changes.inserted == IndexSet(integer: 3) && changes.changed.isEmpty)
        #expect(RowChanges(from: rows([1, 2]), to: rows([1, 2])) { $0.identifier }.isEmpty)
    }

    @Test func aMovedRowGoesAwayAndComesAtItsNewPlace() {
        let changes = RowChanges(from: rows([1, 2, 3, 4]), to: rows([2, 3, 4, 1])) { $0.identifier }
        #expect(changes.removed.count == 1 && changes.inserted.count == 1 && changes.changed.isEmpty)
    }

    /// A table that applies the changes shows the new list and keeps the
    /// views of the rows that stayed.
    @Test(arguments: [([1, 2, 3, 4], [4, 3, 2, 1]), ([1, 2, 3], [0, 3, 9, 1]), ([], [5, 6]), ([7, 8], [])])
    func aTableThatAppliesTheChangesShowsTheNewList(old: [Int], new: [Int]) {
        final class Source: NSObject, NSTableViewDataSource {
            var identifiers: [Int] = []
            func numberOfRows(in tableView: NSTableView) -> Int { identifiers.count }
            func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { identifiers.indices.contains(row) ? identifiers[row] : nil }
        }
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
        let source = Source()
        source.identifiers = old
        table.dataSource = source
        table.reloadData()
        let changes = RowChanges(from: rows(old), to: rows(new, title: "new")) { $0.identifier }
        source.identifiers = new
        var updated: [Int] = []
        changes.apply(to: table, animation: []) { updated.append($0) }
        #expect(table.numberOfRows == new.count)
        #expect(updated == changes.changed.map { $0 })
    }
}
