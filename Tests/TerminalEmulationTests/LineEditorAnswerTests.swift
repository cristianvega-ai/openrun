import Testing
@testable import TerminalEmulation

@Suite struct LineEditorAnswerTests {
    private static func end(of pieces: [String], editor: LineEditor) -> (piece: Int, offset: Int, erasedLines: Bool)? {
        var answer = LineEditorAnswer(editor: editor)
        for (number, piece) in pieces.enumerated() {
            let bytes = Array(piece.utf8)[...]
            if let end = answer.end(in: bytes) { return (number, end.index, end.erasedLines) }
        }
        return nil
    }

    @Test func zshAnswersAfterItsEraseBelow() {
        let answer = "\u{1b}[2A\r\u{1b}[0m\u{1b}[J"
        #expect(Self.end(of: [answer + "prompt> "], editor: .zsh)! == (0, answer.utf8.count, true))
        #expect(Self.end(of: ["\u{1b}[A\r\u{1b}[", "0Jprompt> "], editor: .zsh)! == (1, 2, true))
        #expect(Self.end(of: ["typed text\u{1b}[K"], editor: .zsh) == nil)
    }

    @Test func readlineAnswersAfterItsLastEraseOfARow() {
        let erases = "\r\u{1b}[K\r\u{1b}[A\u{1b}[K\r\u{1b}[A\u{1b}[K"
        #expect(Self.end(of: [erases + "\r$ echo"], editor: .readline)! == (0, erases.utf8.count, true))
        #expect(Self.end(of: ["\r\u{1b}[K\r\u{1b}[A", "\u{1b}[K\r$ echo"], editor: .readline)! == (1, 3, true))
        #expect(Self.end(of: ["\r\u{1b}[K\r", "$ echo"], editor: .readline)! == (1, 0, true))
        #expect(Self.end(of: ["\r\u{1b}[K\r\u{1b}[A\u{1b}[K"], editor: .readline) == nil)
    }

    @Test func theEndOfEditingEndsTheAnswer() {
        let typed = "x\u{1b}[?2004l"
        for editor in [LineEditor.zsh, .readline] {
            #expect(Self.end(of: [typed + "\r\r\noutput"], editor: editor)! == (0, typed.utf8.count, false))
        }
    }
}
