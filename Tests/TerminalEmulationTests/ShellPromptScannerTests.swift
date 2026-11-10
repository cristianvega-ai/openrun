import Testing
@testable import TerminalEmulation

@Suite struct ShellPromptScannerTests {
    private static func hits(in pieces: [String]) -> [(piece: Int, index: Int, event: ShellPromptScanner.Event)] {
        var scanner = ShellPromptScanner()
        return pieces.enumerated().flatMap { number, piece in
            scanner.hits(in: Array(piece.utf8)[...]).map { (number, $0.index, $0.event) }
        }
    }

    /// The bytes that zsh 5.8.1 and 5.9 wrote in a pseudo terminal for a new
    /// prompt, with `TERM=xterm-256color`.
    @Test func findsTheStartOfAZshPrompt() {
        let start = "\r \r\r\u{1b}[0m\u{1b}[27m\u{1b}[24m\u{1b}[J"
        let found = Self.hits(in: [start + "ready> \u{1b}[K\u{1b}[?2004h"])
        #expect(found.map(\.event) == [.zshPromptStart] && found.first?.index == start.utf8.count)
    }

    /// terminfo spells `sgr0` of xterm as `ESC ( B CSI m`.
    @Test func findsTheStartAcrossPiecesAndOtherResets() {
        let found = Self.hits(in: ["\u{1b}(B\u{1b}", "[m\u{1b}[27m\u{1b}[24m\u{1b}[", "0J"])
        #expect(found.map(\.event) == [.zshPromptStart])
        #expect(found.first?.piece == 2 && found.first?.index == 2)
    }

    /// zsh erases a completion list with a bare erase, fish erases after
    /// `sgr0` alone, and a program can erase after one reset of its own.
    @Test(arguments: ["\u{1b}[J", "\u{1b}[0m\u{1b}[J", "\u{1b}(B\u{1b}[m\u{1b}[J", "\u{1b}[27m\u{1b}[24m\u{1b}[1J", "\u{1b}[27m\u{1b}[24mx\u{1b}[J"])
    func anEraseAfterOtherSequencesIsNoStart(_ output: String) {
        #expect(Self.hits(in: [output]).isEmpty)
    }

    @Test func findsTheEndOfEditing() {
        #expect(Self.hits(in: ["ls\u{1b}[?20", "04l\r\n"]).map { [$0.piece, $0.index] } == [[1, 3]])
    }
}

extension ShellPromptScannerTests {
    @Test func findsTheMarksOfASemanticPrompt() {
        let found = Self.hits(in: ["\u{1b}]133;A\u{07}> ", "\u{1b}]133;A;cl=m;aid=7\u{1b}", "\\> ls\u{1b}]133;C;cmdline=" + String(repeating: "l", count: 300) + "\u{07}"])
        #expect(found.map(\.event) == [.markedPromptStart, .markedPromptStart, .commandStart])
        #expect(found.map(\.piece) == [0, 2, 2] && found.map(\.index) == [8, 1, 322])
    }

    /// Another command, or a command that an escape or a cancel ends early.
    @Test(arguments: ["\u{1b}]133;AB\u{07}", "\u{1b}]1337;A\u{07}", "\u{1b}]133;A\u{1b}[m\u{07}", "\u{1b}]133;A\u{18}\u{07}", "\u{1b}]0;133;A\u{07}"])
    func otherCommandsAreNoMarks(_ output: String) {
        #expect(Self.hits(in: [output]).isEmpty)
    }
}
