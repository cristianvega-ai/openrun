import AppKit
import Testing
@testable import ProjectsList

@MainActor @Suite struct ProjectsListControllerTests {
    @Test func theListShowsTheEntriesAndStartsOnAllSessions() {
        let (list, host, window, _) = makeProjectsList()
        defer { window.close() }
        #expect(list.table.numberOfRows == 6 && list.selection == .allSessions && host.selections.isEmpty)
        #expect(list.cell(at: 1)?.name.stringValue == "Needs You" && list.cell(at: 2)?.name.stringValue == "openrun")
        #expect(list.cell(at: 5)?.name.stringValue == "Other Folders")
        list.scroll.scrollerStyle = .legacy
        #expect(list.scroll.scrollerStyle == .overlay)
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

    @Test func theSelectionGoesToAllSessionsWhenItsProjectGoesAway() {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        list.select(.project(identifiers[0]))
        var content = list.content
        content.projects.removeFirst()
        list.show(content)
        #expect(list.table.numberOfRows == 5 && list.selection == .allSessions && host.selections == [.allSessions])
    }

    @Test func theAddButtonAsksTheHostForANewProject() {
        let (list, host, window, _) = makeProjectsList()
        defer { window.close() }
        list.addButton.performClick(nil)
        #expect(host.newProjectRequests == 1 && list.topRow.trailingItems.arrangedSubviews.contains(list.addButton))
    }

    @Test func theUsageOfTheAccountsTakesRoomUnderTheListOnlyWithAReading() {
        let (list, _, window, _) = makeProjectsList()
        defer { window.close() }
        let listHeight = list.scroll.frame.height
        #expect(list.usage.isHidden && listHeight > 300)
        let reading = AccountUsageDisplay(title: "Codex", windows: [.init(name: "Week", usedFraction: 0.4)], readTime: "09:15", help: "")
        list.show(ProjectsListContent(accounts: [reading]))
        window.layoutIfNeeded()
        #expect(!list.usage.isHidden && list.usage.frame.height > 30 && list.scroll.frame.height == listHeight - list.usage.frame.height)
        list.show(ProjectsListContent())
        window.layoutIfNeeded()
        #expect(list.usage.isHidden && list.scroll.frame.height == listHeight)
    }

    @Test func aDraggedProjectMovesAtOnceAndTheHostHearsOfIt() {
        let (list, host, window, identifiers) = makeProjectsList()
        defer { window.close() }
        #expect(list.moveProject(row: 2, dropRow: 5))
        #expect(list.content.projects.map(\.identifier) == [identifiers[1], identifiers[2], identifiers[0]])
        #expect(list.cell(at: 4)?.name.stringValue == "openrun")
        #expect(host.moves.count == 1 && host.moves.first?.0 == identifiers[0] && host.moves.first?.1 == 2)
        #expect(!list.moveProject(row: 1, dropRow: 3) && !list.moveProject(row: 3, dropRow: 3))
    }
}
