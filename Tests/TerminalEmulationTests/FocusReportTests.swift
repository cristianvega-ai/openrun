import Testing
@testable import TerminalEmulation

@Suite struct FocusReportTests {
    @Test func gainAndLossHaveTheirOwnSequences() throws {
        #expect(String(decoding: try FocusReport.encode(gained: true), as: UTF8.self) == "\u{1B}[I")
        #expect(String(decoding: try FocusReport.encode(gained: false), as: UTF8.self) == "\u{1B}[O")
    }
}
