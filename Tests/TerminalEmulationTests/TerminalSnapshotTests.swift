import Testing
@testable import TerminalEmulation

@Suite struct TerminalSnapshotTests {

    private func restore(_ terminal: Terminal) throws -> Terminal {
        try TerminalSnapshot(capturing: terminal).restoreTerminal(scrollbackLimit: 1000)
    }

    @Test func snapshotBytesRestoreFromAnotherArray() throws {
        let terminal = try makeTerminal()
        terminal.write("kept")
        let snapshot = try TerminalSnapshot(capturing: terminal)
        let restored = try TerminalSnapshot(bytes: snapshot.bytes).restoreTerminal(scrollbackLimit: 10)
        #expect(try restored.visibleText() == "kept")
    }

    @Test func truncatedBytesFailToRestore() throws {
        let terminal = try makeTerminal()
        terminal.write("kept")
        let snapshot = try TerminalSnapshot(capturing: terminal)
        let truncated = TerminalSnapshot(bytes: Array(snapshot.bytes.dropLast(8)))
        #expect(throws: TerminalEmulationError.self) {
            _ = try truncated.restoreTerminal(scrollbackLimit: 10)
        }
    }
}
