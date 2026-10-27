import Testing
@testable import TerminalEmulation

@Suite struct PasteTextTests {
    private func encoded(_ text: String, after output: String = "") throws -> String {
        let terminal = try makeTerminal()
        terminal.write(output)
        return String(decoding: try PasteText(text).encoded(for: terminal), as: UTF8.self)
    }

    @Test func plainPasteTurnsLineFeedsIntoCarriageReturns() throws {
        #expect(try encoded("a\nb") == "a\rb")
    }

    @Test func bracketedPasteIsWrapped() throws {
        #expect(try encoded("a\nb", after: "\u{1B}[?2004h") == "\u{1B}[200~a\nb\u{1B}[201~")
    }

    @Test func aPasteCannotEndTheBracketItself() throws {
        #expect(try encoded("x\u{1B}[201~y", after: "\u{1B}[?2004h") == "\u{1B}[200~x [201~y\u{1B}[201~")
    }
}
