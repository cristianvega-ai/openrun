import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsListDraggingTests {
    @Test func aRowMovesOnlyInTheManualOrder() {
        let (list, host, window, identifiers) = makeSessionsList()
        defer { window.close() }
        list.select(identifiers[0])
        #expect(list.moveRow(row: 0, dropRow: 3))
        #expect(list.content.rows.map(\.identifier) == [identifiers[1], identifiers[2], identifiers[0], identifiers[3]])
        #expect(list.shownTitles[2] == "Repair the resize" && list.selection == identifiers[0])
        #expect(host.moves.count == 1 && host.moves.first?.0 == identifiers[0] && host.moves.first?.1 == 2)
        list.arrange(filter: .all, order: .name)
        #expect(!list.moveRow(row: 0, dropRow: 3) && list.tableView(list.table, pasteboardWriterForRow: 0) == nil)
        #expect(host.moves.count == 1)
    }
}
