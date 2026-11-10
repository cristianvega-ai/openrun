import Testing
@testable import TerminalEmulation

@Suite struct CursorLineStartTests {
    /// The mark of zsh's PROMPT_SP and its spaces after output without a line
    /// end, and zsh's erase from the start of the row below.
    private static func zshPrompt(after output: String) -> String {
        output + "%" + String(repeating: " ", count: 39) + "\r \r\r\u{1b}[0m\u{1b}[27m\u{1b}[24m\u{1b}[J"
    }

    /// A wide character or a narrow one can fill the last cell before the
    /// mark. The line break erases neither of them.
    @Test(arguments: [("partial", 25), ("partial", 60), ("partial", 33), (String(repeating: "w", count: 38) + "\u{65E5}", 25),
                      (String(repeating: "w", count: 38) + "\u{65E5}", 60), (String(repeating: "w", count: 39) + "Q", 60)])
    func aCursorAtTheStartOfABlankWrappedRowKeepsItsRow(output: String, columns: Int) throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(Self.zshPrompt(after: output))
        try terminal.resize(to: TerminalSize(columns: UInt16(columns), rows: 10), keeping: .cursorRow)
        #expect(terminal.cursorPosition.column == 0)
        terminal.write("prompt>")
        let text = try terminal.visibleText()
        #expect(text.hasSuffix("\nprompt>") && text.replacingOccurrences(of: "\n", with: "").hasPrefix(output), "\(text)")
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

    /// A row with text is not where a shell erased its lines, and a line
    /// break at the bottom would color a new row with the cursor's style.
    @Test(arguments: [String(repeating: "a", count: 40) + "b\r", zshPrompt(after: "partial") + "\u{1b}[41m"])
    func aRowWithTextOrAColoredCursorFollowsTheReflow(output: String) throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(output)
        try terminal.resize(to: TerminalSize(columns: 60, rows: 10), keeping: .cursorRow)
        #expect(terminal.cursorPosition.column != 0)
    }

    @Test func aChangeOfRowsOnlyKeepsTheWrap() throws {
        let terminal = try makeTerminal(columns: 40, rows: 10)
        terminal.write(Self.zshPrompt(after: "partial"))
        #expect(try terminal.resize(to: TerminalSize(columns: 40, rows: 12), keeping: .cursorRow) == .nothing)
        try terminal.resize(to: TerminalSize(columns: 60, rows: 12))
        #expect(terminal.cursorPosition.column != 0)
    }
}
