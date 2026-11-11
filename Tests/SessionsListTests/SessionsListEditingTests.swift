import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsListEditingTests {
    /// Types `text` into the field editor and ends the edit, as a click elsewhere does.
    private func type(_ text: String, into field: NSTextField, of list: SessionsListController) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        field.window?.makeFirstResponder(list.table)
    }

    @Test func aRowIsRenamedInPlaceAndAnEmptyNameKeepsTheOldOne() throws {
        let (list, host, window, identifiers) = makeSessionsList()
        defer { window.close() }
        list.beginRename(of: identifiers[1])
        let field = try #require(list.cell(at: 1)?.title)
        try type("  server ", into: field, of: list)
        #expect(host.renames.count == 1 && host.renames.first?.0 == identifiers[1] && host.renames.first?.1 == "server")
        #expect(!field.isEditable && window.firstResponder === list.table)
        list.beginRename(of: identifiers[1])
        try type(" ", into: field, of: list)
        #expect(field.stringValue == "zsh" && host.renames.count == 1)
    }

    @Test func theContextMenuRenamesAndCloses() {
        let (list, host, window, identifiers) = makeSessionsList()
        defer { window.close() }
        #expect(list.table.menu?.items.map(\.title) == ["Rename", "Close"])
        list.closeRow(at: 3)
        list.closeRow(at: 9)
        #expect(host.closes == [identifiers[3]])
    }
}
