import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsListControllerTests {
    @Test func theListFiltersAndOrdersTheRowsWithoutAReport() {
        let (list, host, window, _) = makeSessionsList()
        defer { window.close() }
        #expect(list.shownTitles == ["Repair the resize", "zsh", "Write the tests", "logs"] && list.cell(at: 3)?.age.stringValue == "2h")
        list.arrange(filter: .finished, order: .lastActivity)
        #expect(list.shownTitles == ["Write the tests", "zsh", "logs"] && list.table.numberOfRows == 3)
        list.arrange(filter: .inProgress, order: .name)
        #expect(list.shownTitles == ["Repair the resize"] && host.selections.isEmpty)
    }

    /// A new alert changes the text of one row, in the view that it already has.
    @Test func aNewAlertUpdatesOnlyItsRowInPlace() {
        let (list, _, window, _) = makeSessionsList()
        defer { window.close() }
        let cells = (0..<4).map { list.cell(at: $0) }
        var content = list.content
        content.rows[2].alert = "Approve the edit?"
        list.show(content)
        #expect(list.cell(at: 2)?.secondLine.stringValue == "Approve the edit?" && list.cell(at: 2)?.attention.isHidden == false)
        #expect(zip(cells, (0..<4).map { list.cell(at: $0) }).allSatisfy { $0 === $1 })
    }

    /// The title of the list starts where the icons of the rows start.
    @Test func theTitleLinesUpWithTheIconsOfTheRows() throws {
        let (list, _, window, _) = makeSessionsList()
        defer { window.close() }
        let cell = try #require(list.cell(at: 0))
        let title = list.titleLabel.superview!.convert(list.titleLabel.alignmentRect(forFrame: list.titleLabel.frame), to: list.view)
        #expect(cell.icon.imageAlignment == .alignLeft)
        list.scroll.scrollerStyle = .legacy
        #expect(list.scroll.scrollerStyle == .overlay)
        #expect(cell.convert(cell.icon.frame, to: list.view).minX == title.minX)
    }

    @Test func theHostHearsOfASelectionByTheUserAndOfARowThatGoesAway() {
        let (list, host, window, identifiers) = makeSessionsList()
        defer { window.close() }
        list.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        list.select(identifiers[2])
        #expect(host.selections == [identifiers[1]] && list.selection == identifiers[2])
        list.arrange(filter: .all, order: .name)
        #expect(list.selection == identifiers[2] && host.selections.count == 1)
        list.table.openSelected?()
        #expect(host.opens == [identifiers[2]])
        var content = list.content
        content.rows.remove(at: 2)
        list.show(content)
        #expect(list.selection == nil && host.selections == [identifiers[1], nil])
    }
}

@MainActor @Suite struct SessionsListAgeTests {
    /// The age of a finished row grows with the time, in the view that the row already has.
    @Test func anUpdateShowsTheNewAgesInPlace() {
        let (list, _, window, _) = makeSessionsList()
        defer { window.close() }
        let cell = list.cell(at: 2)
        #expect(cell?.age.stringValue == "8m")
        list.now = { Date(timeIntervalSince1970: 10_000 + 3_600) }
        list.update()
        #expect(list.cell(at: 2) === cell && cell?.age.stringValue == "1h")
    }
}
