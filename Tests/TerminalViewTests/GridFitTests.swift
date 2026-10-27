import CoreGraphics
import Testing
import TerminalEmulation
@testable import TerminalView

@Suite struct GridFitTests {
    private func grid(_ width: CGFloat, _ height: CGFloat, scale: CGFloat = 2) -> TerminalSize {
        GridFit.grid(for: CGSize(width: width, height: height), scale: scale, cell: (16, 31), padding: 16)
    }

    @Test func wholeCellsFitInsideThePadding() {
        // (1600 - 32) / 16 = 98 columns, and (800 - 32) / 31 = 24 rows.
        #expect(grid(800, 400) == TerminalSize(columns: 98, rows: 24))
        // A half point is one pixel, and a column needs 16.
        #expect(grid(800.5, 400) == TerminalSize(columns: 98, rows: 24))
        #expect(grid(808, 400) == TerminalSize(columns: 99, rows: 24))
    }

    @Test func aTinyViewStillHasOneCell() {
        #expect(grid(10, 10) == TerminalSize(columns: 1, rows: 1))
        #expect(grid(0, 0) == TerminalSize(columns: 1, rows: 1))
    }

    @Test func aHugeViewStopsAtTheLargestGrid() {
        #expect(grid(1_000_000, 1_000_000) == TerminalSize(columns: Terminal.maximumGridDimension, rows: Terminal.maximumGridDimension))
    }
}
