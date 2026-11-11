import Testing
@testable import TerminalEmulation

@Suite struct ViewportRowTextTests {
    @Test func aRowGivesTheTextOfEachCellAndItsWraps() throws {
        let terminal = try makeTerminal(columns: 6, rows: 3)
        terminal.write("日本abcdefg\r\ne\u{301}")
        let first = try #require(terminal.viewportRowText(at: 0))
        #expect(first.cells == ["日", "", "本", "", "a", "b"])
        #expect(first.widths == [.wide, .wideTail, .wide, .wideTail, .narrow, .narrow])
        #expect(first.wrapsToNextRow && !first.continuesPreviousRow)
        let second = try #require(terminal.viewportRowText(at: 1))
        #expect(second.cells == ["c", "d", "e", "f", "g", ""] && !second.wrapsToNextRow && second.continuesPreviousRow)
        #expect(terminal.viewportRowText(at: 2)?.cells.first == "e\u{301}")
        #expect(terminal.viewportRowText(at: 3) == nil)
    }

    @Test func theRowsFollowTheViewportWhenItScrolls() throws {
        let terminal = try makeTerminal(columns: 6, rows: 2)
        terminal.write("one\r\ntwo\r\nthree")
        terminal.scrollViewport(.byRows(-1))
        #expect(terminal.viewportRowText(at: 0)?.cells.prefix(3).joined() == "one")
    }
}
