import Testing
@testable import TerminalEmulation

@Suite struct RenderStateTests {
    @Test func firstUpdateTakesTheSizeAndMarksEverything() throws {
        let state = try RenderState()
        try state.update(from: makeTerminal(columns: 30, rows: 8))
        #expect(state.size == TerminalSize(columns: 30, rows: 8))
        #expect(state.dirtiness == .everything)
    }

    @Test func markCleanThenTypingMarksSomeRows() throws {
        let terminal = try makeTerminal()
        let state = try RenderState()
        try state.update(from: terminal)
        state.markClean()
        #expect(state.dirtiness == .nothing)
        terminal.write("x")
        try state.update(from: terminal)
        #expect(state.dirtiness == .someRows)
    }

    @Test func splitUpdateGivesTheSameResultAsOneStep() throws {
        let state = try RenderState()
        try state.beginUpdate(from: makeTerminal(columns: 12, rows: 4))
        state.endUpdate()
        #expect(state.size == TerminalSize(columns: 12, rows: 4))
    }

    @Test func colorsFollowTheProgram() throws {
        let terminal = try makeTerminal()
        try terminal.setReplyHandler({ _ in }, colorScheme: { .light })
        terminal.write("\u{1B}]4;1;rgb:aa/bb/cc\u{1B}\\")
        let state = try RenderState()
        try state.update(from: terminal)
        let colors = state.colors
        #expect(colors.background == TerminalColor(red: 255, green: 255, blue: 255))
        #expect(colors.palette.count == 256)
        #expect(colors.palette[1] == TerminalColor(red: 0xAA, green: 0xBB, blue: 0xCC))
    }

    @Test func cursorShowsPositionAndShape() throws {
        let terminal = try makeTerminal()
        terminal.write("ab\r\nc\u{1B}[5 q")
        let state = try RenderState()
        try state.update(from: terminal)
        let cursor = state.cursor
        #expect(cursor.position == TerminalCursorPosition(column: 1, row: 1))
        #expect(cursor.style == .bar)
        #expect(cursor.isBlinking)
        #expect(cursor.isVisible)
    }
}
