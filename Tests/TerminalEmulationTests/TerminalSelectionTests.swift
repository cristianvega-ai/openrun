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
}
