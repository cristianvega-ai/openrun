import Testing
@testable import TerminalEmulation

@Suite struct CursorLineStartTests {
    /// Output without a line end, the mark of zsh's PROMPT_SP, and spaces that
    /// wrap. zsh's erase leaves the cursor at the start of the blank row below.
    private static let wrappedMark = "partial%" + String(repeating: " ", count: 39) + "\r \r\u{1b}[0m\u{1b}[J"

    @Test(arguments: [25, 60, 33])
    func aCursorAtTheStartOfABlankWrappedRowKeepsItsRow(columns: Int) throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(Self.wrappedMark)
        try terminal.resize(to: TerminalSize(columns: UInt16(columns), rows: 10), keeping: .cursorRow)
        #expect(terminal.cursorPosition.column == 0)
        terminal.write("prompt>")
        #expect(try terminal.visibleText().hasSuffix("\nprompt>"))
    }

    /// Without the request, a resize keeps the reflow of libghostty-vt: the
    /// text that follows continues the wrapped line.
    @Test func ordinaryOutputKeepsItsWrappedLine() throws {
        let terminal = try makeTerminal(columns: 40, rows: 8)
        let start = String(repeating: "A", count: 39)
        terminal.write(start + " X\r\u{1b}[K")
        try terminal.resize(to: TerminalSize(columns: 80, rows: 8))
        terminal.write("Z")
        #expect(try terminal.visibleText() == start + " Z")
    }

    @Test(arguments: [
        String(repeating: "a", count: 40) + "b\r\u{1b}[K",
        String(repeating: "a", count: 39) + "\u{1b}[41m \u{1b}[0mb\r\u{1b}[K",
        "partial%" + String(repeating: " ", count: 39) + "\r \r\u{1b}[J\u{1b}[41m",
    ])
    func aCellWithTextOrColorStaysAndSoDoesTheWrap(output: String) throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(output)
        let (before, cursor) = (try terminal.formatted(.virtualTerminalSequences), terminal.cursorPosition)
        try terminal.resize(to: TerminalSize(columns: 60, rows: 10), keeping: .cursorRow)
        // The wrap stays, so the cursor follows the wrapped line.
        #expect(terminal.cursorPosition.column != 0)
        try terminal.resize(to: TerminalSize(columns: 40, rows: 10))
        #expect(try terminal.formatted(.virtualTerminalSequences) == before)
        #expect(terminal.cursorPosition == cursor)
    }

    @Test func aChangeOfRowsOnlyKeepsTheWrap() throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(Self.wrappedMark)
        try terminal.resize(to: TerminalSize(columns: 40, rows: 12), keeping: .cursorRow)
        try terminal.resize(to: TerminalSize(columns: 60, rows: 12))
        #expect(terminal.cursorPosition.column != 0)
    }
}
