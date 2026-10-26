import Testing
@testable import TerminalEmulation

@Suite struct TerminalModeTests {
    @Test func aProgramTurnsModesOnAndOff() throws {
        let terminal = try makeTerminal()
        #expect(!terminal.isModeEnabled(.applicationCursorKeys))
        terminal.write("\u{1B}[?1h\u{1B}[?2004h\u{1B}[?1004h")
        #expect(terminal.isModeEnabled(.applicationCursorKeys))
        #expect(terminal.isModeEnabled(.bracketedPaste))
        #expect(terminal.isModeEnabled(.focusReports))
        terminal.write("\u{1B}[?1l")
        #expect(!terminal.isModeEnabled(.applicationCursorKeys))
    }

    @Test func everyModeReadsItsOwnNumber() throws {
        let terminal = try makeTerminal()
        for mode in TerminalMode.allCases {
            let before = TerminalMode.allCases.map(terminal.isModeEnabled)
            try terminal.setMode(mode, enabled: !terminal.isModeEnabled(mode))
            let after = TerminalMode.allCases.map(terminal.isModeEnabled)
            #expect(zip(before, after).filter { $0 != $1 }.count == 1, "\(mode)")
            try terminal.setMode(mode, enabled: !terminal.isModeEnabled(mode))
        }
    }

    @Test func mouseModesFollowTheProgram() throws {
        let terminal = try makeTerminal()
        terminal.write("\u{1B}[?1000h\u{1B}[?1003h")
        #expect(terminal.isModeEnabled(.normalMouseReports) && terminal.isModeEnabled(.anyMouseReports))
        #expect(!terminal.isModeEnabled(.buttonMouseReports))
    }
}
