import AppKit
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectsListControllerTests {
    @Test func theListShowsTheEntriesAndStartsOnAllSessions() {
        let (list, host, window, _) = makeProjectsList()
        defer { window.close() }
        #expect(list.table.numberOfRows == 6 && list.selection == .allSessions && host.selections.isEmpty)
        #expect(list.cell(at: 1)?.name.stringValue == "Needs You" && list.cell(at: 2)?.name.stringValue == "openrun")
        #expect(list.cell(at: 5)?.name.stringValue == "No Project")
    }

    @Test func aSelectionByTheUserReachesTheHost() {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        list.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(host.selections == [.project(identifiers[1]), .needsYou])
        list.select(.noProject)
        #expect(list.selection == .noProject && host.selections.count == 2)
    }

    /// A new count changes the text of one row, in the view that it already has.
    @Test func aNewCountUpdatesOnlyItsRowInPlace() throws {
        let (list, _, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.select(.project(identifiers[2]))
        let cells = (0..<6).map { list.cell(at: $0) }
        var content = list.content
        (content.projects[0].attentionCount, content.needsYouCount) = (2, 2)
        list.show(content)
        #expect(list.cell(at: 2)?.count.stringValue == "2" && list.cell(at: 3)?.count.stringValue == "")
        #expect(list.cell(at: 1)?.count.stringValue == "2" && list.cell(at: 0)?.count.stringValue == "")
        #expect(zip(cells, (0..<6).map { list.cell(at: $0) }).allSatisfy { $0 === $1 })
        #expect(list.selection == .project(identifiers[2]))
    }
}
