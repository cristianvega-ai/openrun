import CoreGraphics
import Foundation
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct SelectionInputTests {
    /// 80 by 24 cells of 8 by 15.5 points, with 8 points of padding, on a screen with scale 2.
    private let location = PointerLocation(cellSize: CGSize(width: 8, height: 15.5), padding: 8, scale: 2, gridSize: TerminalSize(columns: 80, rows: 24), viewHeight: 388)

    private func makeInput() throws -> (SelectionInput, Terminal) {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 100)
        terminal.write("one two three\r\nsecond line")
        return (try SelectionInput(terminal: terminal), terminal)
    }

    /// The middle of the cell in a column and a row.
    private func cell(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: 8 + 8 * (CGFloat(column) + 0.5), y: 388 - 8 - 15.5 * (CGFloat(row) + 0.5))
    }

    @Test func aDragSelectsTheCellsFromThePressToThePointer() throws {
        let (input, terminal) = try makeInput()
        input.press(at: cell(4, 0), in: location, timestamp: 1)
        // The right half of a cell is part of the selection.
        let end = CGPoint(x: cell(6, 0).x + 3, y: cell(6, 0).y)
        input.drag(to: end, in: location)
        input.release(at: end, in: location)
        #expect(terminal.selectedText() == "two")
    }

    @Test func quickClicksSelectAWordAndALineAndASinglePressClearsTheSelection() throws {
        let (input, terminal) = try makeInput()
        func click(_ time: TimeInterval) {
            input.press(at: cell(5, 0), in: location, timestamp: time)
            input.release(at: cell(5, 0), in: location)
        }
        click(1)
        #expect(!terminal.hasSelection)
        click(1.1)
        #expect(terminal.selectedText() == "two")
        click(1.2)
        #expect(terminal.selectedText() == "one two three")
        click(10)
        #expect(!terminal.hasSelection)
    }
}
