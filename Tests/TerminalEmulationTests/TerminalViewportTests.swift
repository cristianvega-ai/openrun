import Testing
@testable import TerminalEmulation

@Suite struct TerminalViewportTests {
    /// Ten lines in a screen of three rows leave seven lines of scrollback.
    private func scrolledTerminal() throws -> Terminal {
        let terminal = try makeTerminal(columns: 10, rows: 3)
        terminal.write((0..<10).map { "line\($0)" }.joined(separator: "\r\n"))
        return terminal
    }

    @Test func startsAtTheBottomOfTheScrollback() throws {
        let terminal = try scrolledTerminal()
        #expect(terminal.isViewportAtBottom)
        #expect(terminal.scrollbar == Scrollbar(totalRows: 10, firstVisibleRow: 7, visibleRows: 3))
    }

    @Test func scrollsByRowsToTheTopAndBack() throws {
        let terminal = try scrolledTerminal()
        terminal.scrollViewport(.byRows(-2))
        #expect(!terminal.isViewportAtBottom && terminal.scrollbar.firstVisibleRow == 5)
        terminal.scrollViewport(.toTop)
        #expect(terminal.scrollbar.firstVisibleRow == 0)
        terminal.scrollViewport(.toRow(4))
        #expect(terminal.scrollbar.firstVisibleRow == 4)
        terminal.scrollViewport(.toBottom)
        #expect(terminal.isViewportAtBottom)
    }

    @Test func outputKeepsAScrolledViewportInPlace() throws {
        let terminal = try scrolledTerminal()
        terminal.scrollViewport(.toTop)
        terminal.write("\r\nmore")
        #expect(!terminal.isViewportAtBottom && terminal.scrollbar.firstVisibleRow == 0)
    }
}
