import Testing
@testable import TerminalEmulation

func makeTerminal(columns: UInt16 = 20, rows: UInt16 = 5, scrollbackLimit: Int = 1000) throws -> Terminal {
    try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: scrollbackLimit)
}

@Suite struct TerminalTests {

    @Test func failedCreationReportsTheResultCode() {
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal(size: TerminalSize(columns: 0, rows: 0), scrollbackLimit: 10)
        }
    }
}
