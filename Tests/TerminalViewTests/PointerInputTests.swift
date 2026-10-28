import AppKit
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
        #expect(pixel.horizontalPosition == 86 && pixel.verticalPosition == 101)
        #expect(location.cell(of: point) == ViewportCell(column: 5, row: 3))
    }

    @Test func aPointOutsideTheGridGivesTheNearestEdge() {
        #expect(location.cell(of: CGPoint(x: -50, y: 1000)) == ViewportCell(column: 0, row: 0))
        #expect(location.cell(of: CGPoint(x: 5000, y: -50)) == ViewportCell(column: 79, row: 23))
        let corner = location.pixel(of: CGPoint(x: 5000, y: -50))
        #expect(corner.horizontalPosition == 1279 && corner.verticalPosition == 743)
    }
}

@MainActor @Suite struct PointerShapeCursorTests {
    @Test func everyShapeHasACursorOfMacOS() {
        let expected: [(PointerShape, NSCursor)] = [
            (.text, .iBeam), (.arrow, .arrow), (.pointingHand, .pointingHand), (.crosshair, .crosshair), (.notAllowed, .operationNotAllowed),
            (.openHand, .openHand), (.closedHand, .closedHand), (.resizeLeftRight, .resizeLeftRight), (.resizeUpDown, .resizeUpDown), (.other, .iBeam),
        ]
        for (shape, cursor) in expected { #expect(PointerShapeCursor.cursor(for: shape) === cursor, "\(shape)") }
    }

    @Test func theViewFollowsTheShapeThatTheProgramAsksFor() throws {
        let view = try TerminalView()
        #expect(view.pointerCursor === NSCursor.iBeam)
        view.write(Array("\u{1B}]22;pointer\u{07}".utf8))
        view.parseTurn()
        #expect(view.pointerCursor === NSCursor.pointingHand)
        view.write(Array("\u{1B}]22;default\u{07}".utf8))
        view.parseTurn()
        #expect(view.pointerCursor === NSCursor.arrow)
    }
}
