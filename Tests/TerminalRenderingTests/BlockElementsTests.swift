import Testing
@testable import TerminalRendering

@Suite struct BlockElementsTests {
    private func canvas(_ character: Character, width: Int = 16, height: Int = 31) -> CellCanvas {
        var canvas = CellCanvas(width: width, height: height)
        #expect(BlockElements.draw(character.unicodeScalars.first!, on: &canvas))
        return canvas
    }

    private func inkRows(_ canvas: CellCanvas) -> [Int] { (0..<canvas.height).filter { canvas.coverage(column: 0, row: $0) == 255 } }

    @Test func halvesCompleteEachOtherWithNoGapAndNoOverlapAtEveryTextSize() {
        for (width, height) in drawnCellSizes {
            for (first, second) in [("▀", "▄"), ("▌", "▐"), ("▘", "▟"), ("▝", "▙"), ("▖", "▜"), ("▗", "▛"), ("▚", "▞")] {
                let one = canvas(Character(first), width: width, height: height), other = canvas(Character(second), width: width, height: height)
                let sums = zip(one.pixels, other.pixels).map { Int($0) + Int($1) }
                #expect(sums.allSatisfy { $0 == 255 }, "\(first)\(second) \(width)x\(height)")
            }
        }
    }

    @Test func theEighthsGrowFromTheirEdge() {
        let lower = (0x2581...0x2588).map { inkRows(canvas(Character(Unicode.Scalar($0)!))) }
        #expect(lower.allSatisfy { $0.last == 30 })
        #expect(zip(lower, lower.dropFirst()).allSatisfy { $0.count < $1.count })
        #expect(lower.last?.count == 31)
        #expect(inkRows(canvas("▔")) == [0, 1, 2, 3])
        #expect(canvas("▕").coverage(column: 15, row: 0) == 255 && canvas("▕").coverage(column: 13, row: 0) == 0)
        #expect(canvas("▏").coverage(column: 0, row: 0) == 255 && canvas("▏").coverage(column: 2, row: 0) == 0)
    }

    @Test func theShadesAreEvenPartsOfTheColor() {
        #expect(Set(canvas("░").pixels) == [64] && Set(canvas("▒").pixels) == [128] && Set(canvas("▓").pixels) == [191])
        #expect(Set(canvas("█").pixels) == [255])
    }

    @Test func aBarOfBlocksFillsItsCellsOnTheScreen() throws {
        let screen = try renderScreen("\u{1B}[?25l██\r\n██", columns: 3, rows: 2)
        let foreground = screen.theme.foreground
        for (column, row, horizontal, vertical) in [(0, 0, 0, 0), (0, 0, testFonts.cellWidth - 1, testFonts.cellHeight - 1), (1, 1, 0, 0)] {
            #expect(pixel(of: screen.target, column: column, row: row, horizontalPosition: horizontal, verticalPosition: vertical) == foreground)
        }
        #expect(inkCount(of: screen, columns: 0..<2, rows: 0..<2) == 4 * testFonts.cellWidth * testFonts.cellHeight)
    }
}
