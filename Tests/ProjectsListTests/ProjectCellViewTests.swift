import AppKit
import Foundation
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectCellViewTests {
    @Test func theCellShowsTheNameTheCountAndTheFolder() throws {
        let project = ProjectDisplay(identifier: UUID(), name: "openrun", folder: "/p/openrun", attentionCount: 2)
        let rows = ProjectsListRow.rows(for: ProjectsListContent(projects: [project]))
        let cell = ProjectCellView()
        cell.show(rows[3])
        #expect(cell.name.stringValue == "openrun" && cell.count.stringValue == "2" && cell.toolTip == "/p/openrun")
        #expect(cell.icon.image != nil)
        #expect(cell.accessibilityLabel() == "openrun, 2 need you")
        cell.show(rows[0])
        #expect(cell.name.stringValue == "All Projects" && cell.count.stringValue.isEmpty && cell.toolTip?.contains("Every thread") == true)
    }

    @Test func theHeadingOfTheProjectsIsQuietTextWithNoIconAndNoCount() {
        let heading = ProjectsHeadingCellView()
        heading.show(ProjectsListRow(kind: .heading, name: "Projects", symbol: "", help: nil, attentionCount: 0))
        #expect(heading.label.stringValue == "Projects" && heading.subviews == [heading.label] && heading.accessibilityLabel() == "Projects")
        #expect(ProjectsHeadingCellView.headingHeight > ProjectCellView.height && ProjectsHeadingCellView.hintHeight < ProjectCellView.height)
    }

    /// A cut name keeps at least 8 points from the count. A label can draw
    /// its text up to its frame, 2 points past its alignment rectangle.
    @Test func aCutNameKeepsItsDistanceFromTheCount() {
        let project = ProjectDisplay(identifier: UUID(), name: "infrastructure-terraform-modules", folder: "/p/i", attentionCount: 1)
        let cell = ProjectCellView()
        cell.show(ProjectsListRow.rows(for: ProjectsListContent(projects: [project]))[3])
        cell.layoutSubtreeIfNeeded()
        #expect(cell.name.frame.width < cell.name.intrinsicContentSize.width)
        #expect(cell.count.alignmentRect(forFrame: cell.count.frame).minX - cell.name.frame.maxX >= 8)
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
        cell.show(ProjectsListRow.rows(for: ProjectsListContent(projects: [project]))[3])
        cell.name.isEditable = true
        window.makeFirstResponder(cell.name)
        let editor = try #require(cell.name.currentEditor() as? NSTextView)
        editor.insertText("site", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        cell.show(ProjectsListRow.rows(for: ProjectsListContent(projects: [project], needsYouCount: 1))[2])
        #expect(editor.string == "site")
    }
}
