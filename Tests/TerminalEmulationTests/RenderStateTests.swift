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
}
