import CoreGraphics
import Testing
@testable import TerminalRendering

@Suite struct CellCanvasTests {
    @Test func aFillCoversWholePixelsAndStopsAtTheEdges() {
        var canvas = CellCanvas(width: 4, height: 3)
        canvas.fill(left: -2, top: 1, right: 2, bottom: 9)
        #expect(canvas.pixels == [0, 0, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0])
        #expect(canvas.coverage(column: 9, row: 0) == 0)
    }

    @Test func aWeakerFillDoesNotLightenAStrongerOne() {
        var canvas = CellCanvas(width: 2, height: 1)
        canvas.fill(left: 0, top: 0, right: 2, bottom: 1)
        canvas.fill(left: 1, top: 0, right: 2, bottom: 1, coverage: 64)
        #expect(canvas.pixels == [255, 255])
    }

    @Test func aDrawingCountsFromTheTopLeft() {
        var canvas = CellCanvas(width: 4, height: 4)
        canvas.draw { $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1)) }
        #expect(canvas.coverage(column: 0, row: 0) == 255)
        #expect(canvas.coverage(column: 0, row: 3) == 0)
    }

    @Test func theLightThicknessFollowsTheWidthOfTheCell() {
        #expect(CellCanvas(width: 4, height: 9).lightThickness == 1)
        #expect(CellCanvas(width: 16, height: 31).lightThickness == 2)
        #expect(CellCanvas(width: 87, height: 170).lightThickness == 11)
    }

    @Test func theBitmapCoversTheCellFromItsCorner() {
        let bitmap = CellCanvas(width: 16, height: 31).bitmap
        #expect(bitmap.width == 16 && bitmap.height == 31 && bitmap.horizontalOffset == 0 && bitmap.verticalOffset == 0)
    }
}
