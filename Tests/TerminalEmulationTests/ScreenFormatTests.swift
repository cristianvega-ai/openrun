import Testing
@testable import TerminalEmulation

@Suite struct ScreenFormatTests {
    private let styledOutput = "plain \u{1b}[1;31mbold red\u{1b}[0m \u{1b}[38;2;10;20;30mtrue color\u{1b}[0m\r\nsecond\u{1b}[4munder\u{1b}[0m\u{1b}[3;5H*"

    @Test func plainTextDropsStyles() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write(styledOutput)
        #expect(try terminal.visibleText() == "plain bold red true color\nsecondunder\n    *")
    }

    /// What libghostty-vt writes for the screen, without the palette and the
    /// tab stops that come first. The bytes here come from the sequences of the
    /// Control Sequence Introducer standard, not from the formatter: bold is
    /// `1`, palette color 1 is `38;5;1`, true color is `38;2;red;green;blue`,
    /// underline is `4`, and `[3;6H` puts the cursor after the star.
    private func screenBody(of terminal: Terminal) throws -> String {
        let output = String(decoding: try terminal.formatted(.virtualTerminalSequences), as: UTF8.self)
        let home = try #require(output.range(of: "\u{1b}[H"))
        return String(output[home.lowerBound...])
    }

    @Test func virtualTerminalSequencesCarryStyles() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write(styledOutput)
        #expect(try screenBody(of: terminal) == "\u{1b}[Hplain \u{1b}[0m\u{1b}[1m\u{1b}[38;5;1mbold red\u{1b}[0m \u{1b}[0m\u{1b}[38;2;10;20;30mtrue color\u{1b}[0m\r\nsecond\u{1b}[0m\u{1b}[4munder\u{1b}[0m\r\n    *\u{1b}[3;6H\u{1b}[0m")
    }

    @Test func virtualTerminalSequencesCarryCursorVisibilityModesAndLinks() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("\u{1b}[?25l\u{1b}[?2004h\u{1b}[?1h\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7} x")
        let output = String(decoding: try terminal.formatted(.virtualTerminalSequences), as: UTF8.self)
        #expect(output.contains("\u{1b}[?25l"), "hidden cursor")
        #expect(output.contains("\u{1b}[?2004h"), "bracketed paste")
        #expect(output.contains("\u{1b}[?1h"), "application cursor keys")
        #expect(try screenBody(of: terminal) == "\u{1b}[H\u{1b}]8;;https://example.com\u{1b}\\link\u{1b}]8;;\u{1b}\\ x\u{1b}[1;7H\u{1b}[0m")
    }

    @Test func aVisibleCursorAndPlainModesLeaveNoSequences() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("text")
        let output = String(decoding: try terminal.formatted(.virtualTerminalSequences), as: UTF8.self)
        #expect(!output.contains("\u{1b}[?25l"))
        #expect(!output.contains("\u{1b}[?2004h"))
        #expect(!output.contains("\u{1b}[?1h"))
    }

    @Test func virtualTerminalSequencesReproduceTheScrollback() throws {
        let original = try makeTerminal(columns: 20, rows: 3)
        // The last line has no line break: the formatter drops blank rows at
        // the bottom, so a trailing break would shorten the copy's scrollback.
        original.write((1...12).map { "\u{1b}[3\($0 % 7 + 1)mline \($0)\u{1b}[0m" }.joined(separator: "\r\n"))
        let sequences = try original.formatted(.virtualTerminalSequences, extent: .withScrollback)

        let copy = try makeTerminal(columns: 20, rows: 3)
        copy.write(sequences)

        #expect(try copy.formatted(.plainText, extent: .withScrollback) == original.formatted(.plainText, extent: .withScrollback))
        #expect(copy.scrollbackLineCount == original.scrollbackLineCount)
    }

    @Test func visibleExtentLeavesOutScrollback() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        for number in 1...8 {
            terminal.write("line \(number)\r\n")
        }
        let visible = String(decoding: try terminal.formatted(.plainText, extent: .visible), as: UTF8.self)
        let everything = String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
        #expect(!visible.contains("line 1"))
        #expect(visible.contains("line 8"))
        #expect(everything.contains("line 1"))
        #expect(everything.contains("line 8"))
    }
}
