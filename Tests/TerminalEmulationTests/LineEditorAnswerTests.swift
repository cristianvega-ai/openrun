import Testing
@testable import TerminalEmulation

/// Draws as zsh does after SIGWINCH: up to its first line by the row count of
/// its last drawing, an erase below, and the lines again.
private struct FakeZsh {
    var lines: [String]
    /// The rows from the first line to the cursor, at the width of the last drawing.
    var cursorLine = 0

    mutating func draw(width: Int) -> String {
        let up = cursorLine > 0 ? "\u{1b}[\(cursorLine)A" : ""
        cursorLine = lines.dropLast().reduce(0) { $0 + max(1, ($1.count + width - 1) / width) } + (lines.last!.count - 1) / width
        return up + "\r\u{1b}[0m\u{1b}[J" + lines.joined(separator: "\r\n")
    }
}

/// A copy of a screen that takes a new size where the line editor's answer
/// has erased its lines, as the session process does.
private final class FollowingScreen {
    let terminal: Terminal
    private var waitingSize: TerminalSize?
    private var answer = LineEditorAnswer(editor: .zsh)

    init(columns: UInt16, rows: UInt16) throws {
        terminal = try makeTerminal(columns: columns, rows: rows)
    }

    func resize(to size: TerminalSize, editor: LineEditor) {
        waitingSize = size
        answer = LineEditorAnswer(editor: editor)
    }

    func write(_ text: String) throws {
        let bytes = Array(text.utf8)[...]
        guard let size = waitingSize, let end = answer.end(in: bytes) else {
            terminal.write(bytes)
            return
        }
        terminal.write(bytes[..<end.index])
        try terminal.resize(to: size, keepingCursorAtLineStart: end.erasedLines)
        waitingSize = nil
        terminal.write(bytes[end.index...])
    }

    /// The screen and the scrollback without the line breaks that wrapping adds.
    func unwrappedText() throws -> String {
        String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "")
    }
}

@Suite struct LineEditorAnswerTests {
    /// The widths of a window that shrinks and grows again.
    static let widths = [60, 25, 15, 60, 40]

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

    @Test func aLongInputLineKeepsTheOutputAboveIt() throws {
        let screen = try FollowingScreen(columns: 40, rows: 10)
        var zsh = FakeZsh(lines: ["prompt> " + String(repeating: "x", count: 50)])
        try screen.write("earlier output\r\n" + zsh.draw(width: 40))
        for width in Self.widths {
            screen.resize(to: TerminalSize(columns: UInt16(width), rows: 10), editor: .zsh)
            try screen.write(zsh.draw(width: width))
        }
        #expect(try screen.unwrappedText() == "earlier output" + zsh.lines[0])
    }

    @Test func aPromptOfTwoLinesIsDrawnOnce() throws {
        let screen = try FollowingScreen(columns: 40, rows: 10)
        var zsh = FakeZsh(lines: ["header " + String(repeating: "h", count: 45), "% "])
        try screen.write("earlier output\r\n" + zsh.draw(width: 40))
        for width in Self.widths {
            screen.resize(to: TerminalSize(columns: UInt16(width), rows: 10), editor: .zsh)
            try screen.write(zsh.draw(width: width))
        }
        #expect(try screen.unwrappedText() == "earlier output" + zsh.lines.joined().trimmingCharacters(in: .whitespaces))
    }
}
