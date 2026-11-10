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
}
