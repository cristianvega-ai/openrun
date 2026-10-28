import Testing
@testable import TerminalEmulation

/// A client draws with the widths of the session only when its terminal has
/// the same mode 2027 as the terminal of the session.
@Suite struct GraphemeClusterTests {
    @Test func theSnapshotAndThePictureCarryModeTwentyTwentySeven() throws {
        let terminal = try makeTerminal()
        #expect(!terminal.isModeEnabled(.graphemeClusters))
        terminal.write("\u{1B}[?2027h\u{2764}\u{FE0F}x")
        // The emoji takes two cells, so the cursor is after column 2.
        #expect(terminal.cursorPosition == TerminalCursorPosition(column: 3, row: 0))
        let restored = try TerminalSnapshot(capturing: terminal).restoreTerminal(scrollbackLimit: 10)
        #expect(restored.isModeEnabled(.graphemeClusters) && restored.cursorPosition == terminal.cursorPosition)
        // `openrun attach` draws this picture, so the window turns the mode on too.
        #expect(String(decoding: try restored.formatted(.virtualTerminalSequences), as: UTF8.self).contains("\u{1B}[?2027h"))
    }
}
