import Testing
@testable import TerminalEmulation

@Suite struct TerminalSelectionTests {
    @Test func aDoubleClickSelectsTheWord() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write("one two   three")
        #expect(!terminal.hasSelection && terminal.selectedText() == nil)
        try terminal.selectWord(at: ViewportCell(column: 5, row: 0))
        #expect(terminal.hasSelection && terminal.selectedText() == "two")
        terminal.clearSelection()
        #expect(!terminal.hasSelection)
    }

    @Test func aTripleClickSelectsTheWholeWrappedLine() throws {
        let terminal = try makeTerminal(columns: 10, rows: 4)
        terminal.write("0123456789abcde\r\nnext")
        try terminal.selectLine(at: ViewportCell(column: 3, row: 1))
        #expect(terminal.selectedText() == "0123456789abcde")
    }

    @Test func selectAllTakesTheScrollbackAndTheScreen() throws {
        let terminal = try makeTerminal(columns: 10, rows: 3)
        terminal.write((1...8).map { "line \($0)" }.joined(separator: "\r\n"))
        #expect(terminal.scrollbackLineCount == 5)
        try terminal.selectAll()
        #expect(terminal.selectedText() == (1...8).map { "line \($0)" }.joined(separator: "\n"))
        terminal.write("\u{1B}[?1049h\u{1B}[Halternate")
        try terminal.selectAll()
        #expect(terminal.selectedText() == "alternate")
    }

    @Test func readsTheLinkUnderACell() throws {
        let terminal = try makeTerminal(columns: 20, rows: 2)
        terminal.write("\u{1B}]8;;https://example.com\u{07}link\u{1B}]8;;\u{07} plain")
        #expect(terminal.hyperlink(at: ViewportCell(column: 2, row: 0)) == "https://example.com")
        #expect(terminal.hyperlink(at: ViewportCell(column: 8, row: 0)) == nil)
    }
}
