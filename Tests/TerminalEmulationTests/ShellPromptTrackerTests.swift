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

    /// fish turns bracketed paste off and on while it draws its prompt.
    /// Only its mark of a command ends the prompt.
    @Test func aPromptMarkEndsAtTheMarkOfACommand() throws {
        let tracker = try Self.tracker(writing: "out\u{1b}[?2004h\u{1b}]133;A\u{07}> ")
        #expect(tracker.prompt == .init(editor: .markedPrompt, rowsAboveCursor: 0))
        tracker.write(Array("\u{1b}[?2004l".utf8)[...])
        #expect(tracker.prompt == nil)
        tracker.write(Array("\u{1b}[?2004hls".utf8)[...])
        #expect(tracker.prompt?.editor == .markedPrompt)
        tracker.write(Array("\u{1b}]133;C\u{07}".utf8)[...])
        #expect(tracker.prompt == nil)
    }

    /// After output without a line end, zsh's prompt starts on a row that
    /// continues the output. A reflow joins that row to the output, and the
    /// kept rows put the prompt below it again.
    @Test func aResizeKeepsTheFirstRowOfThePrompt() throws {
        let output = "partial%" + String(repeating: " ", count: 19) + "\r \r" + Self.zshPrompt + "typed"
        for keeping in [PromptKeeping.cursorRow, .promptRows(aboveCursor: 1)] {
            let tracker = try Self.tracker(columns: 20, rows: 8, writing: output)
            if keeping == .cursorRow { tracker.write(Array("\r\u{1b}[A\u{1b}[0m\u{1b}[27m\u{1b}[24m\u{1b}[J".utf8)[...]) }
            #expect(try tracker.resize(to: TerminalSize(columns: 40, rows: 8), keeping: keeping) == keeping)
            #expect(tracker.prompt?.rowsAboveCursor == (keeping == .cursorRow ? 0 : 1))
        }
    }
}
