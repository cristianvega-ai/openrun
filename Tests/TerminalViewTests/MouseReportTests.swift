import CoreGraphics
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct MouseReporterTests {
    /// 80 by 24 cells of 8 by 15.5 points, with 8 points of padding, on a screen with scale 2.
    private let location = PointerLocation(cellSize: CGSize(width: 8, height: 15.5), padding: 8, scale: 2, gridSize: TerminalSize(columns: 80, rows: 24), viewHeight: 388)

    private func cellPoint(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: 8 + 8 * CGFloat(column) + 3, y: 388 - (8 + 15.5 * CGFloat(row) + 4))
    }

    private func bytes(_ reporter: MouseReporter, _ action: MouseEvent.Action, _ button: MouseEvent.Button?, _ column: Int, _ row: Int) -> String {
        String(decoding: reporter.bytes(action, button: button, modifiers: [], at: cellPoint(column, row), in: location), as: UTF8.self)
    }

    @Test func aProgramGetsReportsOnlyWhenItAsksForThem() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 0)
        let reporter = try MouseReporter(terminal: terminal)
        #expect(!reporter.isActive && bytes(reporter, .press, .left, 5, 3) == "")
        terminal.write("\u{1B}[?1002h\u{1B}[?1006h")
        #expect(bytes(reporter, .press, .left, 5, 3) == "\u{1B}[<0;6;4M")
        #expect(bytes(reporter, .motion, .left, 6, 3) == "\u{1B}[<32;7;4M")
        #expect(bytes(reporter, .release, .left, 6, 3) == "\u{1B}[<0;7;4m")
        #expect(bytes(reporter, .press, .forward, 1, 1) == "\u{1B}[<129;2;2M")
        #expect(bytes(reporter, .press, .wheelUp, 0, 0) == "\u{1B}[<64;1;1M")
    }

    @Test func theEncoderReadsTheModesAgainOnlyWhenTheyChange() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 0)
        terminal.write("\u{1B}[?1003h\u{1B}[?1006h")
        let reporter = try MouseReporter(terminal: terminal)
        #expect(bytes(reporter, .motion, nil, 5, 3) == "\u{1B}[<35;6;4M")
        #expect(bytes(reporter, .motion, nil, 5, 3) == "")
        terminal.write("\u{1B}[?1006l")
        #expect(bytes(reporter, .motion, nil, 5, 3) == "\u{1B}[MC&$")
    }
}
