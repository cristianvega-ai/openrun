import Testing
@testable import TerminalRendering

@Suite struct BraillePatternTests {
    private func canvas(_ value: UInt32, width: Int = 16, height: Int = 31) -> CellCanvas {
        var canvas = CellCanvas(width: width, height: height)
        #expect(BraillePattern.draw(Unicode.Scalar(value)!, on: &canvas))
        return canvas
    }

    /// The coverage of the middle of each dot, in the order of the bits.
    private func dots(_ canvas: CellCanvas) -> [Bool] {
        let places = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
        return places.map { column, row in
            canvas.coverage(column: canvas.width * (2 * column + 1) / 4, row: canvas.height * (2 * row + 1) / 8) > 128
        }
    }

    @Test func eachBitShowsItsDot() {
        for bit in 0..<8 {
            let shown = dots(canvas(0x2800 + (1 << bit)))
            #expect(shown == (0..<8).map { $0 == bit }, "bit \(bit)")
        }
        #expect(canvas(0x2800).pixels.allSatisfy { $0 == 0 })
        #expect(dots(canvas(0x28FF)).allSatisfy { $0 })
    }

    @Test func theDotsKeepTheirDistanceAcrossTwoCellsAtEveryTextSize() {
        for (width, height) in drawnCellSizes {
            let full = canvas(0x28FF, width: width, height: height)
            let inkColumns = (0..<width).filter { column in (0..<height).contains { full.coverage(column: column, row: $0) > 128 } }
            let inkRows = (0..<height).filter { row in (0..<width).contains { full.coverage(column: $0, row: row) > 128 } }
            // The space at the two edges together is about the space between two dots, within a pixel.
            let edges = inkColumns.first! + (width - 1 - inkColumns.last!)
            let between = zip(inkColumns, inkColumns.dropFirst()).map { $1 - $0 - 1 }.max()!
            #expect(abs(edges - between) <= 1, "\(width)x\(height)")
            #expect(inkRows.first! + (height - 1 - inkRows.last!) <= height / 4 + 1, "\(width)x\(height)")
            #expect(!inkColumns.isEmpty && inkColumns.last! < width && inkRows.last! < height)
        }
    }

    @Test func otherCharactersAreNotBraille() {
        var canvas = CellCanvas(width: 16, height: 31)
        #expect(!BraillePattern.draw("A", on: &canvas) && !BraillePattern.draw("\u{2900}", on: &canvas))
    }
}
