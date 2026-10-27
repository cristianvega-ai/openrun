import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct PasteInputTests {
    @Test func onlyTextWithALineBreakAndNoBracketedPasteAsksFirst() {
        #expect(!UnsafePasteRule.needsQuestion(for: "ls -la", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\necho b", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\r\n", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\r", bracketedPaste: false))
        #expect(!UnsafePasteRule.needsQuestion(for: "line\n".repeated(500), bracketedPaste: true))
    }

    @Test func aBracketedPasteHasItsMarksAndAPlainPasteHasCarriageReturns() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 5), scrollbackLimit: 0)
        func bytes(_ text: String) -> String { String(decoding: PasteInput.bytes(for: text, terminal: terminal), as: UTF8.self) }
        #expect(bytes("a\nb") == "a\rb")
        terminal.write("\u{1B}[?2004h")
        #expect(bytes("a\nb") == "\u{1B}[200~a\nb\u{1B}[201~")
        #expect(bytes("x\u{1B}[201~rm") == "\u{1B}[200~x [201~rm\u{1B}[201~")
    }
}

private extension String {
    func repeated(_ count: Int) -> String { String(repeating: self, count: count) }
}
