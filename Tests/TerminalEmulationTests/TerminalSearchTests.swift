import Testing
@testable import TerminalEmulation

@Suite struct TerminalSearchTests {
    /// A terminal of three rows with eight lines, so five are scrollback.
    private func makeSearch() throws -> (terminal: Terminal, search: TerminalSearch) {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write((1...8).map { "line \($0) Apple" }.joined(separator: "\r\n"))
        return (terminal, try TerminalSearch(terminal: terminal))
    }

    @Test func theNewestMatchIsSelectedAndTheStepsGoThroughTheScrollback() throws {
        let (terminal, search) = try makeSearch()
        // The letters of ASCII match in each case.
        #expect(try search.find("apple") == TerminalSearch.Matches(count: 8, selected: 1))
        #expect(terminal.selectedText() == "Apple")
        #expect(try search.selectOlder() == TerminalSearch.Matches(count: 8, selected: 2))
        for _ in 3...8 { _ = try search.selectOlder() }
        // The oldest match is in the scrollback, and the viewport went to it.
        #expect(!terminal.isViewportAtBottom)
        // After the oldest match comes the newest one, and back.
        #expect(try search.selectOlder().selected == 1)
        #expect(try search.selectNewer().selected == 8)
    }

    @Test func aTextWithNoMatchAndAnEmptyTextSelectNothing() throws {
        let (terminal, search) = try makeSearch()
        _ = try search.find("line 7")
        #expect(terminal.selectedText() == "line 7")
        #expect(try search.find("pear") == TerminalSearch.Matches(count: 0, selected: nil))
        #expect(!terminal.hasSelection)
        #expect(try search.selectOlder() == TerminalSearch.Matches())
        _ = try search.find("line 7")
        #expect(try search.find("") == TerminalSearch.Matches() && !terminal.hasSelection)
    }

    @Test func aStepSeesTheOutputThatCameAfterTheSearchStarted() throws {
        let (terminal, search) = try makeSearch()
        #expect(try search.find("apple").count == 8)
        terminal.write("\r\nline 9 apple")
        #expect(try search.selectOlder().count == 9)
    }
}
