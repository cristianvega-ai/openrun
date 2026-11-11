import Testing
@testable import TerminalRendering

@Suite struct BoxDrawingShapesTests {
    private func canvas(_ character: Character, width: Int, height: Int) -> CellCanvas {
        var canvas = CellCanvas(width: width, height: height)
        if let arms = BoxLineArms(character.unicodeScalars.first!) { arms.draw(on: &canvas) } else {
            #expect(BoxDrawingShapes.draw(character.unicodeScalars.first!, on: &canvas))
        }
        return canvas
    }

    private func column(_ canvas: CellCanvas, _ index: Int) -> [UInt8] { (0..<canvas.height).map { canvas.coverage(column: index, row: $0) } }
    private func row(_ canvas: CellCanvas, _ index: Int) -> [UInt8] { (0..<canvas.width).map { canvas.coverage(column: $0, row: index) } }

    @Test func roundedCornersMeetTheLightLinesExactlyAtEveryTextSize() {
        for (width, height) in drawnCellSizes {
            let horizontal = canvas("─", width: width, height: height), vertical = canvas("│", width: width, height: height)
            let downRight = canvas("╭", width: width, height: height), downLeft = canvas("╮", width: width, height: height)
            let upLeft = canvas("╯", width: width, height: height), upRight = canvas("╰", width: width, height: height)
            #expect(column(downRight, width - 1) == column(horizontal, 0), "\(width)x\(height)")
            #expect(row(downRight, height - 1) == row(vertical, 0), "\(width)x\(height)")
            #expect(column(downLeft, 0) == column(horizontal, width - 1) && row(downLeft, height - 1) == row(vertical, 0))
            #expect(column(upLeft, 0) == column(horizontal, 0) && row(upLeft, 0) == row(vertical, 0), "\(width)x\(height)")
            #expect(column(upRight, width - 1) == column(horizontal, 0) && row(upRight, 0) == row(vertical, height - 1))
            // A corner has no line at its other two edges.
            #expect(row(downRight, 0).allSatisfy { $0 == 0 } && column(downRight, 0).allSatisfy { $0 == 0 }, "\(width)x\(height)")
        }
    }

    @Test func dashesHaveEvenGapsAlsoBetweenTwoCells() {
        let dashed = canvas("┄", width: 16, height: 31)
        let line = row(dashed, 15).map { $0 > 0 }
        let joined = line + line
        // The lengths of the gaps along two cells next to each other.
        var gaps: [Int] = [], current = 0
        for isInk in joined.dropFirst(joined.firstIndex(of: true)!) {
            if isInk { if current > 0 { gaps.append(current) }; current = 0 } else { current += 1 }
        }
        #expect(gaps.count == 5 && Set(gaps).count == 1, "\(gaps)")
        #expect(row(canvas("┆", width: 16, height: 31), 0).contains { $0 == 0 })
    }

    @Test func smallCellsKeepAGapInEveryDashedLine() {
        for (width, height) in drawnCellSizes {
            for character in "┄┅┈┉╌╍" { #expect(row(canvas(character, width: width, height: height), height / 2).contains(0), "\(character) \(width)") }
            for character in "┆┇┊┋╎╏" { #expect(column(canvas(character, width: width, height: height), width / 2).contains(0), "\(character) \(width)") }
        }
    }

    @Test func diagonalsReachTheCornersOfTheCell() {
        let rising = canvas("╱", width: 16, height: 31), falling = canvas("╲", width: 16, height: 31), cross = canvas("╳", width: 16, height: 31)
        #expect(rising.coverage(column: 15, row: 0) > 0 && rising.coverage(column: 0, row: 30) > 0 && rising.coverage(column: 0, row: 0) == 0)
        #expect(falling.coverage(column: 0, row: 0) > 0 && falling.coverage(column: 15, row: 30) > 0 && falling.coverage(column: 15, row: 0) == 0)
        #expect(cross.coverage(column: 0, row: 0) > 0 && cross.coverage(column: 15, row: 0) > 0)
    }
}
