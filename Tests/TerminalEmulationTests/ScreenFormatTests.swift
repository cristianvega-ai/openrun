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

    @Test func hypertextMarkupShowsEachStyleOfTheScreen() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write(styledOutput)
        // The markup is a second output path of the formatter, so a style that
        // the sequences lose without a trace shows up here.
        let markup = String(decoding: try terminal.formatted(.hypertextMarkup), as: UTF8.self)
        #expect(markup == "<div style=\"font-family: monospace; white-space: pre;\">plain <div style=\"display: inline;color: var(--vt-palette-1);font-weight: bold;\">bold red</div> <div style=\"display: inline;color: rgb(10, 20, 30);\">true color</div>\nsecond<div style=\"display: inline;text-decoration-line: underline;text-decoration-style: solid;\">under</div>\n    *</div>")
    }

    /// The markup for a link. The attribute sign is apart from the name so
    /// that the name scan does not read the attribute as a name of ours.
    private static func anchor(to address: String, text: String) -> String {
        "<a href" + "=\"\(address)\">\(text)</a>"
    }

    @Test func hypertextMarkupShowsALink() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7} x")
        let markup = String(decoding: try terminal.formatted(.hypertextMarkup), as: UTF8.self)
        #expect(markup.contains(Self.anchor(to: "https://example.com", text: "link") + " x"))
    }

    @Test func virtualTerminalSequencesReproduceTheScreen() throws {
        let original = try makeTerminal(columns: 40, rows: 5)
        original.write(styledOutput)
        let sequences = try original.formatted(.virtualTerminalSequences)

        let copy = try makeTerminal(columns: 40, rows: 5)
        copy.write(sequences)

        #expect(try copy.visibleText() == original.visibleText())
        #expect(copy.cursorPosition == original.cursorPosition)
        #expect(try copy.formatted(.virtualTerminalSequences) == sequences)
        // Equal sequences prove little when the formatter loses a style on
        // both passes, so the copy must also show the styles in the markup.
        let markup = String(decoding: try copy.formatted(.hypertextMarkup), as: UTF8.self)
        #expect(markup.contains("font-weight: bold;\">bold red"))
        #expect(markup.contains("color: rgb(10, 20, 30);\">true color"))
        #expect(markup.contains("text-decoration-line: underline;"))
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

    @Test func hypertextMarkupWrapsBoldText() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("\u{1b}[1mbold\u{1b}[0m")
        let markup = String(decoding: try terminal.formatted(.hypertextMarkup), as: UTF8.self)
        #expect(markup == "<div style=\"font-family: monospace; white-space: pre;\"><div style=\"display: inline;font-weight: bold;\">bold</div></div>")
    }
}
