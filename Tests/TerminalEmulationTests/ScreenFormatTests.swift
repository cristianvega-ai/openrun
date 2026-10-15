import Testing
@testable import TerminalEmulation

@Suite struct ScreenFormatTests {
    private let styledOutput = "plain \u{1b}[1;31mbold red\u{1b}[0m \u{1b}[38;2;10;20;30mtrue color\u{1b}[0m\r\nsecond\u{1b}[4munder\u{1b}[0m\u{1b}[3;5H*"

    @Test func plainTextDropsStyles() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write(styledOutput)
        #expect(try terminal.visibleText() == "plain bold red true color\nsecondunder\n    *")
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
