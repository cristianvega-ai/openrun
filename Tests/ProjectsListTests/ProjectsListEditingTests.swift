import AppKit
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectsListEditingTests {
    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    /// Types `text` into the field editor and ends the edit, as a click elsewhere does.
    private func type(_ text: String, into field: NSTextField, of list: ProjectsListController) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        field.window?.makeFirstResponder(list.table)
    }

    @Test func returnRenamesTheSelectedProjectInPlace() throws {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.select(.project(identifiers[1]))
        list.table.keyDown(with: try key(36, "\r", in: window))
        let field = try #require(list.cell(at: 4)?.name)
        #expect(field.isEditable && field.currentEditor() != nil)
        try type("  site  ", into: field, of: list)
        #expect(host.renames.count == 1 && host.renames.first?.0 == identifiers[1] && host.renames.first?.1 == "site")
        #expect(!field.isEditable && window.firstResponder === list.table)
    }

    @Test func anEmptyNameOrEscapeKeepsTheOldName() throws {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.beginRename(of: identifiers[0])
        let field = try #require(list.cell(at: 3)?.name)
        try type("   ", into: field, of: list)
        #expect(field.stringValue == "openrun")
        list.beginRename(of: identifiers[0])
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("other", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(list.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(field.stringValue == "openrun" && host.renames.isEmpty)
    }

    @Test func commandDeleteRemovesOnlyAProject() throws {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.table.keyDown(with: try key(51, "\u{7F}", .command, in: window))
        #expect(host.removals.isEmpty)
        list.select(.project(identifiers[2]))
        list.table.keyDown(with: try key(51, "\u{7F}", .command, in: window))
        #expect(host.removals == [identifiers[2]])
        list.table.keyDown(with: try key(36, "\r", in: window))
        list.select(.allSessions)
        list.table.keyDown(with: try key(36, "\r", in: window))
        #expect(list.cell(at: 0)?.name.isEditable == false)
    }
}
