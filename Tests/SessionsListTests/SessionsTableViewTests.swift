import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsTableViewTests {
    /// A table with three rows of nothing, enough for a selection.
    private final class Rows: NSObject, NSTableViewDataSource {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    }

    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func returnOpensOnlyASelectedRow() throws {
        let table = SessionsTableView(), rows = Rows()
        table.dataSource = rows
        var opens = 0
        table.openSelected = { opens += 1 }
        table.keyDown(with: try key(36, "\r"))
        #expect(opens == 0)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.keyDown(with: try key(36, "\r"))
        table.keyDown(with: try key(76, "\u{3}"))
        table.keyDown(with: try key(36, "\r", .shift))
        #expect(opens == 2)
        #expect(table.rowHeight == SessionCellView.height && table.accessibilityLabel() == "Sessions")
    }
}
