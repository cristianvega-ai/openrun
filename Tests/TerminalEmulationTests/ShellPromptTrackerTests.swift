import Testing
@testable import TerminalEmulation

@Suite struct ShellPromptTrackerTests {
    /// The start of a zsh prompt of two lines, and bracketed paste as zsh
    /// turns it on after the prompt.
    static let zshPrompt = "\r\u{1b}[0m\u{1b}[27m\u{1b}[24m\u{1b}[J" + "header\r\n% " + "\u{1b}[?2004h"

    private static func tracker(columns: UInt16 = 20, rows: UInt16 = 5, writing output: String) throws -> ShellPromptTracker {
        let tracker = ShellPromptTracker(terminal: try makeTerminal(columns: columns, rows: rows))
        tracker.write(Array(output.utf8)[...])
        return tracker
    }

    @Test func findsTheFirstRowOfAZshPrompt() throws {
        #expect(try Self.tracker(writing: "out\r\n" + Self.zshPrompt).prompt == .init(editor: .zsh, rowsAboveCursor: 1))
        // The input wraps and scrolls the screen, and the row moves with it.
        let input = String(repeating: "x", count: 70)
        #expect(try Self.tracker(writing: "out\r\n" + Self.zshPrompt + input).prompt?.rowsAboveCursor == 4)
    }

    /// zsh's bytes must start at the first column, while bracketed paste is
    /// on. The end of editing or the alternate screen ends the prompt.
    @Test(arguments: ["out" + zshPrompt.dropFirst(), zshPrompt.replacingOccurrences(of: "\u{1b}[?2004h", with: ""), zshPrompt + "ls\u{1b}[?2004l\r\n", zshPrompt + "\u{1b}[?1049h"])
    func otherOutputHasNoPrompt(_ output: String) throws {
        #expect(try Self.tracker(writing: output).prompt == nil)
    }
}
