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

    @Test func theMatchesOfTheViewportComeWithTheirCells() throws {
        let (terminal, search) = try makeSearch()
        #expect(search.viewportMatches().isEmpty)
        _ = try search.find("apple")
        // The three rows of the viewport hold the lines 6 to 8, each with one match in the columns 7 to 11.
        let matches = search.viewportMatches().sorted { $0.first.row < $1.first.row }
        #expect(matches.map(\.first) == (0...2).map { ViewportCell(column: 7, row: $0) })
        #expect(matches.map(\.last) == (0...2).map { ViewportCell(column: 11, row: $0) })
        // The selected match is the newest one, in the last row. It shows as the selection.
        #expect(search.viewportMatches(includesSelected: false).map(\.first.row).sorted() == [0, 1])
        // The list follows the output that came after the search started.
        terminal.write("\r\nno fruit here")
        #expect(search.viewportMatches().map(\.first.row).sorted() == [0, 1])
        _ = try search.find("pear")
        #expect(search.viewportMatches().isEmpty)
    }

    @Test func aStepSeesTheOutputThatCameAfterTheSearchStarted() throws {
        let (terminal, search) = try makeSearch()
        #expect(try search.find("apple").count == 8)
        terminal.write("\r\nline 9 apple")
        #expect(try search.selectOlder().count == 9)
    }
}
