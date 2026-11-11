import AppKit
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectsTableViewTests {
    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func theTableHasOneColumnOfRowsOfOneHeight() {
        let table = ProjectsTableView()
        #expect(table.tableColumns.count == 1 && table.headerView == nil && table.rowHeight == ProjectCellView.height)
        #expect(!table.allowsEmptySelection && table.accessibilityLabel() == "Projects")
    }

    /// Return and Enter rename, as in the Finder. Delete alone removes nothing.
    @Test func returnRenamesAndCommandDeleteRemoves() throws {
        let table = ProjectsTableView()
        var (renames, removals) = (0, 0)
        table.renameSelected = { renames += 1 }
        table.removeSelected = { removals += 1 }
        table.keyDown(with: try key(36, "\r"))
        table.keyDown(with: try key(76, "\u{3}"))
        table.keyDown(with: try key(51, "\u{7F}"))
        table.keyDown(with: try key(51, "\u{7F}", .command))
        table.keyDown(with: try key(36, "\r", .command))
        #expect(renames == 2 && removals == 1)
    }
}
