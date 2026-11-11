import Testing
@testable import TerminalRendering

@Suite struct PowerlineSymbolsTests {
    private func canvas(_ value: UInt32, width: Int = 16, height: Int = 31) -> CellCanvas {
        var canvas = CellCanvas(width: width, height: height)
        #expect(PowerlineSymbols.draw(Unicode.Scalar(value)!, on: &canvas))
        return canvas
    }

    @Test func aSolidArrowFillsItsFlatEdgeFromTopToBottomAtEveryTextSize() {
        for (width, height) in drawnCellSizes {
            let right = canvas(0xE0B0, width: width, height: height), left = canvas(0xE0B2, width: width, height: height)
            #expect((0..<height).allSatisfy { right.coverage(column: 0, row: $0) > 0 }, "\(width)x\(height)")
            #expect((0..<height).allSatisfy { left.coverage(column: width - 1, row: $0) > 0 }, "\(width)x\(height)")
            // The point is in the middle of the opposite edge.
            #expect(right.coverage(column: width - 1, row: height / 2) > 0 && right.coverage(column: width - 1, row: 0) == 0)
            #expect((0..<height).allSatisfy { canvas(0xE0B4, width: width, height: height).coverage(column: 0, row: $0) > 0 })
        }
    }

    @Test func aThinArrowIsALineAndNotAFill() {
        let thin = canvas(0xE0B1)
        #expect(thin.coverage(column: 0, row: 0) > 0 && thin.coverage(column: 15, row: 15) > 0)
        #expect(thin.coverage(column: 2, row: 15) == 0)
    }

    @Test func theSlopesFillTheirHalfOfTheCell() {
        let lowerLeft = canvas(0xE0B8), upperRight = canvas(0xE0BE)
        #expect(lowerLeft.coverage(column: 0, row: 30) == 255 && lowerLeft.coverage(column: 15, row: 0) == 0)
        #expect(upperRight.coverage(column: 15, row: 0) == 255 && upperRight.coverage(column: 0, row: 30) == 0)
        let slope = canvas(0xE0B9)
        #expect(slope.coverage(column: 0, row: 0) > 0 && slope.coverage(column: 0, row: 30) == 0)
        var other = CellCanvas(width: 16, height: 31)
        #expect(!PowerlineSymbols.draw("\u{E0C0}", on: &other) && !PowerlineSymbols.draw("A", on: &other))
    }
}
