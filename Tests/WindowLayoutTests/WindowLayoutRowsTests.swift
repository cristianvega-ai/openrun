import Foundation
import Testing
@testable import WindowLayout

@Suite struct WindowLayoutRowsTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func aNewSessionGetsARowAtTheTopAndAnEndedOneLeaves() {
        var layout = WindowLayout()
        layout.follow(sessions: [a, b])
        #expect(layout.rows == [LayoutRow(session: b), LayoutRow(session: a)])
        layout.selectedRow = a
        layout.follow(sessions: [b, c])
        #expect(layout.rows.map(\.identifier) == [c, b])
        #expect(layout.selectedRow == nil)
        #expect(layout.row(showing: b)?.identifier == b && layout.row(a) == nil)
    }

    @Test func aRowKeepsItsIdentifierWhenItsFirstSplitEnds() {
        let split = LayoutPane.split(LayoutSplit(direction: .sideBySide, first: .session(a), second: .session(b)))
        var layout = WindowLayout(rows: [LayoutRow(identifier: a, pane: split)], selectedRow: a)
        layout.follow(sessions: [a, b])
        #expect(layout.rows == [LayoutRow(identifier: a, pane: split)])
        layout.follow(sessions: [b])
        #expect(layout.rows == [LayoutRow(identifier: a, pane: .session(b))])
        #expect(layout.selectedRow == a && layout.row(showing: b)?.identifier == a)
    }

    @Test func aRowOrASessionThatTheFileNamesTwiceStaysOnce() {
        var layout = WindowLayout(rows: [LayoutRow(session: a), LayoutRow(session: a), LayoutRow(identifier: b, pane: .session(a)), LayoutRow(session: b)])
        layout.follow(sessions: [a, b])
        #expect(layout.rows == [LayoutRow(session: a), LayoutRow(session: b)])
    }

    @Test func aThreadGetsARowAndStaysUntilTheAppKnowsThatItClosed() throws {
        var layout = WindowLayout()
        layout.follow(sessions: [a], threads: [b])
        #expect(layout.rows == [LayoutRow(thread: b), LayoutRow(session: a)])
        #expect(layout.row(showing: b)?.identifier == b && layout.rows[0].pane.threads == [b] && layout.rows[0].pane.sessions.isEmpty)
        // The app does not know the threads now, such as before their first list.
        layout.follow(sessions: [])
        #expect(layout.rows == [LayoutRow(thread: b)])
        let data = try JSONEncoder().encode(layout.rows)
        #expect(try JSONDecoder().decode([LayoutRow].self, from: data) == layout.rows)
        #expect(String(decoding: data, as: UTF8.self).contains(#""thread":"#))
        layout.follow(sessions: [], threads: [])
        #expect(layout.rows.isEmpty)
    }

    @Test func aMoveAmongTheShownRowsLeavesTheOtherRowsInPlace() {
        var layout = WindowLayout(rows: [a, b, c, d].map { LayoutRow(session: $0) })
        // The list shows the rows of one project: a, c and d.
        layout.moveRow(d, toIndex: 0, among: [a, c, d])
        #expect(layout.rows.map(\.identifier) == [d, a, b, c])
        layout.moveRow(d, toIndex: 2, among: [d, a, c])
        #expect(layout.rows.map(\.identifier) == [a, b, c, d])
        layout.moveRow(a, toIndex: 1, among: [a, c, d])
        #expect(layout.rows.map(\.identifier) == [b, c, a, d])
        layout.moveRow(UUID(), toIndex: 0, among: [a, c, d])
        layout.moveRow(b, toIndex: 5, among: [b])
        #expect(layout.rows.map(\.identifier) == [b, c, a, d])
    }
}
