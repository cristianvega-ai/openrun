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

    @Test func resizeChangesTheSize() throws {
        let terminal = try makeTerminal(columns: 20, rows: 5)
        terminal.write("hello")
        try terminal.resize(to: TerminalSize(columns: 40, rows: 10))
        #expect(terminal.size == TerminalSize(columns: 40, rows: 10))
        #expect(try terminal.visibleText() == "hello")
    }

    @Test func resizeStoresTheSizeOfTheGridInDots() throws {
        // A program that turned on in-band size reports (mode 2048) hears the
        // new size at each resize, in pixels as well. A cell is 8 by 16.
        let terminal = try makeTerminal(columns: 80, rows: 24)
        var replies: [String] = []
        let recorder = ResizeReportRecorder()
        try terminal.setReplyHandler { recorder.append($0) }
        terminal.write("\u{1B}[?2048h")
        try terminal.resize(to: TerminalSize(columns: 100, rows: 40))
        replies = recorder.texts
        // CSI 48 ; rows ; columns ; height ; width t
        #expect(replies.contains("\u{1B}[48;40;100;640;800t"), "replies: \(replies.map { $0.debugDescription })")
        #expect(!replies.contains { $0.hasSuffix(";0;0t") })
    }

    @Test func resizeReflowsWrappedText() throws {
        let terminal = try makeTerminal(columns: 10, rows: 5)
        terminal.write("0123456789abcde")
        try terminal.resize(to: TerminalSize(columns: 20, rows: 5))
        let unwrapped = String(decoding: try terminal.formatted(.plainText), as: UTF8.self)
        #expect(unwrapped == "0123456789abcde")
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

    @Test func anOversizedOrEmptyResizeIsRefusedAndKeepsTheOldSize() throws {
        let terminal = try makeTerminal(columns: 20, rows: 5)
        let tooLarge = Terminal.maximumGridDimension + 1
        #expect(throws: TerminalEmulationError.self) {
            try terminal.resize(to: TerminalSize(columns: tooLarge, rows: 5))
        }
        #expect(throws: TerminalEmulationError.self) {
            try terminal.resize(to: TerminalSize(columns: 0, rows: 5))
        }
        #expect(terminal.size == TerminalSize(columns: 20, rows: 5))
    }

    @Test func theLargestAllowedGridWorks() throws {
        let side = Terminal.maximumGridDimension
        let terminal = try Terminal(size: TerminalSize(columns: side, rows: 4), scrollbackLimit: 10)
        #expect(terminal.size.columns == side)
    }

    @Test func theUnfinishedSequenceCapLeavesRoomInTheSnapshotFrame() {
        // The socket protocol refuses frames above 64 MiB. A snapshot also
        // holds the screens and the scrollback, so the cap must stay well
        // below that.
        #expect(Terminal.continuationByteLimit <= 32 * 1024 * 1024)
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

private final class ResizeReportRecorder {
    private(set) var texts: [String] = []
    func append(_ bytes: [UInt8]) { texts.append(String(decoding: bytes, as: UTF8.self)) }
}
