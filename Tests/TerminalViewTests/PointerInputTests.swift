import CoreGraphics
import TerminalEmulation
import Testing
@testable import TerminalView

@Suite struct PointerLocationTests {
    /// 80 by 24 cells of 8 by 15.5 points, with 8 points of padding, on a screen with scale 2.
    private let location = PointerLocation(
        cellSize: CGSize(width: 8, height: 15.5), padding: 8, scale: 2, gridSize: TerminalSize(columns: 80, rows: 24), viewHeight: 388)

    @Test func aPointOfTheViewGivesAPixelOfTheGridAndItsCell() {
        let point = CGPoint(x: 51, y: 329.5)
        let pixel = location.pixel(of: point)
        #expect(pixel.x == 86 && pixel.y == 101)
        #expect(location.cell(of: point) == ViewportCell(column: 5, row: 3))
    }

    @Test func aPointOutsideTheGridGivesTheNearestEdge() {
        #expect(location.cell(of: CGPoint(x: -50, y: 1000)) == ViewportCell(column: 0, row: 0))
        #expect(location.cell(of: CGPoint(x: 5000, y: -50)) == ViewportCell(column: 79, row: 23))
        let corner = location.pixel(of: CGPoint(x: 5000, y: -50))
        #expect(corner.x == 1279 && corner.y == 743)
    }
}
