import AppKit
import Foundation
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectCellViewTests {
    @Test func theCellShowsTheNameTheCountAndTheFolder() throws {
        let project = ProjectDisplay(identifier: UUID(), name: "openrun", folder: "/p/openrun", attentionCount: 2)
        let rows = ProjectsListRow.rows(for: ProjectsListContent(projects: [project]))
        let cell = ProjectCellView()
        cell.show(rows[2])
        #expect(cell.name.stringValue == "openrun" && cell.count.stringValue == "2" && cell.toolTip == "/p/openrun")
        #expect(cell.icon.image != nil)
        #expect(cell.accessibilityLabel() == "openrun, 2 need you")
        cell.show(rows[0])
        #expect(cell.name.stringValue == "All Sessions" && cell.count.stringValue.isEmpty && cell.toolTip == nil)
    }

    /// A new count while the user edits the name must not undo the edit.
    @Test func theNameStaysWhileTheUserEditsIt() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let cell = ProjectCellView()
        window.contentView = cell
        let project = ProjectDisplay(identifier: UUID(), name: "openrun", folder: "/p/openrun")
        cell.show(ProjectsListRow.rows(for: ProjectsListContent(projects: [project]))[2])
        cell.name.isEditable = true
        window.makeFirstResponder(cell.name)
        let editor = try #require(cell.name.currentEditor() as? NSTextView)
        editor.insertText("site", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        cell.show(ProjectsListRow.rows(for: ProjectsListContent(projects: [project], needsYouCount: 1))[2])
        #expect(editor.string == "site")
    }
}
