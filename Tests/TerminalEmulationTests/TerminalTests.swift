import Testing
@testable import TerminalEmulation

func makeTerminal(columns: UInt16 = 20, rows: UInt16 = 5, scrollbackLimit: Int = 1000) throws -> Terminal {
    try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: scrollbackLimit)
}

extension Terminal {
    func visibleText() throws -> String {
        String(decoding: try formatted(.plainText), as: UTF8.self)
    }
}

@Suite struct TerminalTests {
    @Test func writtenTextAppearsOnTheScreen() throws {
        let terminal = try makeTerminal()
        terminal.write("hello\r\nworld")
        #expect(try terminal.visibleText() == "hello\nworld")
    }

    @Test func reportsSizeAndCursorPosition() throws {
        let terminal = try makeTerminal(columns: 30, rows: 8)
        #expect(terminal.size == TerminalSize(columns: 30, rows: 8))
        terminal.write("abc\r\nde")
        #expect(terminal.cursorPosition == TerminalCursorPosition(column: 2, row: 1))
    }


    @Test func linesThatScrollOffTheTopBecomeScrollback() throws {
        let terminal = try makeTerminal(columns: 10, rows: 3)
        for number in 1...10 {
            terminal.write("line \(number)\r\n")
        }
        #expect(terminal.scrollbackLineCount > 0)
        let everything = String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
        #expect(everything.hasPrefix("line 1\nline 2\n"))
        #expect(try !terminal.visibleText().contains("line 1\n"))
    }

    @Test func failedCreationReportsTheResultCode() {
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal(size: TerminalSize(columns: 0, rows: 0), scrollbackLimit: 10)
        }
    }

    @Test func writingEmptyBytesChangesNothing() throws {
        let terminal = try makeTerminal()
        terminal.write([UInt8]())
        #expect(try terminal.visibleText() == "")
    }

    // MARK: - Validation

    @Test func aNegativeScrollbackLimitIsRefused() {
        #expect(throws: TerminalEmulationError.self) {
            _ = try makeTerminal(scrollbackLimit: -1)
        }
        #expect(throws: TerminalEmulationError.self) {
            _ = try makeTerminal(scrollbackLimit: Int.min)
        }
    }

    @Test func anExcessiveScrollbackLimitIsRefused() {
        #expect(throws: TerminalEmulationError.self) {
            _ = try makeTerminal(scrollbackLimit: Terminal.maximumScrollbackLines + 1)
        }
        #expect(throws: TerminalEmulationError.self) {
            _ = try makeTerminal(scrollbackLimit: Int.max)
        }
    }

    @Test func scrollbackLimitsFromZeroToTheMaximumAreAccepted() throws {
        _ = try makeTerminal(scrollbackLimit: 0)
        _ = try makeTerminal(scrollbackLimit: Terminal.maximumScrollbackLines)
    }

    @Test func aRestoredTerminalAlsoValidatesTheScrollbackLimit() throws {
        let snapshot = try TerminalSnapshot(capturing: makeTerminal())
        #expect(throws: TerminalEmulationError.self) {
            _ = try snapshot.restoreTerminal(scrollbackLimit: -5)
        }
    }

    @Test func anOversizedGridIsRefusedOnCreation() {
        let tooLarge = Terminal.maximumGridDimension + 1
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal(size: TerminalSize(columns: tooLarge, rows: 5), scrollbackLimit: 10)
        }
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal(size: TerminalSize(columns: 5, rows: tooLarge), scrollbackLimit: 10)
        }
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal(size: TerminalSize(columns: UInt16.max, rows: UInt16.max), scrollbackLimit: 10)
        }
    }

    @Test func theLargestAllowedGridWorks() throws {
        let side = Terminal.maximumGridDimension
        let terminal = try Terminal(size: TerminalSize(columns: side, rows: 4), scrollbackLimit: 10)
        #expect(terminal.size.columns == side)
    }

    @Test func theVisibleCornersOfAnEmptyGridAreRefusedInsteadOfUnderflowing() throws {
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal.lastCell(of: TerminalSize(columns: 0, rows: 5))
        }
        #expect(throws: TerminalEmulationError.self) {
            _ = try Terminal.lastCell(of: TerminalSize(columns: 5, rows: 0))
        }
        let corner = try Terminal.lastCell(of: TerminalSize(columns: 20, rows: 5))
        #expect(corner.x == 19)
        #expect(corner.y == 4)
    }
}
