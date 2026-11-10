import Testing
@testable import TerminalEmulation

@Suite struct PromptRowsTests {
    static let line = String(repeating: "L", count: 70)
    /// zsh's start of a prompt, a first line, and a second line with the cursor.
    static let draw = "\u{1b}[0m\u{1b}[27m\u{1b}[24m\u{1b}[J" + line + "\r\n> "

    /// zsh's answer to a new size: up by the rows above the cursor at the
    /// width of its last drawing, and the prompt again.
    private static func answer(rowsUp: Int) -> String {
        "\r" + String(repeating: "\u{1b}[A", count: rowsUp) + draw
    }

    private static func screen(columns: Int) -> String {
        let rows = stride(from: 0, to: line.count, by: columns).map { String(line.dropFirst($0).prefix(columns)) }
        return (["out-1", "out-2"] + rows + [">"]).joined(separator: "\n")
    }

    /// The screen takes each size before zsh answers it, as at the time
    /// limit. Each late answer must land on the first row of the prompt.
    @Test func aLateAnswerLandsOnThePrompt() throws {
        let terminal = try makeTerminal(columns: 80, rows: 10)
        terminal.write("out-1\r\nout-2\r\n" + Self.draw)
        var rowsUp = 1
        for columns in [50, 80, 30, 80, 100, 20, 80] {
            let kept = try terminal.resize(to: TerminalSize(columns: UInt16(columns), rows: 10), keeping: .promptRows(aboveCursor: rowsUp))
            #expect(kept == .promptRows(aboveCursor: rowsUp))
            terminal.write(Self.answer(rowsUp: rowsUp))
            rowsUp = (Self.line.count + columns - 1) / columns
            #expect(try terminal.visibleText() == Self.screen(columns: columns), "\(columns) columns")
        }
    }

    /// Without the rows, the reflow changes the rows of the prompt, and the
    /// late answer leaves part of the old prompt.
    @Test func aPlainReflowLosesTheLateAnswer() throws {
        let terminal = try makeTerminal(columns: 80, rows: 10)
        terminal.write("out-1\r\nout-2\r\n" + Self.draw)
        try terminal.resize(to: TerminalSize(columns: 30, rows: 10))
        terminal.write(Self.answer(rowsUp: 1))
        #expect(try terminal.visibleText() != Self.screen(columns: 30))
    }

    /// A prompt above the screen, or a cursor style with a background, keeps
    /// the plain reflow: the erase cannot reach the prompt, or would color it.
    @Test(arguments: [(9, ""), (1, "\u{1b}[44m")])
    func aPromptThatCannotBeErasedReflows(rowsUp: Int, style: String) throws {
        let terminal = try makeTerminal(columns: 80, rows: 10)
        terminal.write("out-1\r\nout-2\r\n" + Self.draw + style)
        #expect(try terminal.resize(to: TerminalSize(columns: 30, rows: 10), keeping: .promptRows(aboveCursor: rowsUp)) == .nothing)
        #expect(try terminal.visibleText().hasPrefix("out-1\nout-2\nL"))
    }
}
