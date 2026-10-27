import AppKit
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

@MainActor @Suite struct SelectionOfViewTests {
    private func makeView(_ output: String = "") throws -> TerminalView {
        let view = try TerminalView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutSubtreeIfNeeded()
        view.terminal.write("one two three\r\n" + output)
        return view
    }

    /// A mouse event in a column of row 0. A selection starts at the left half of a cell and ends at the right half.
    private func event(_ type: NSEvent.EventType, column: Int, in view: TerminalView, _ flags: NSEvent.ModifierFlags = [], at time: TimeInterval = 1) throws -> NSEvent {
        let cell = view.cellSize, padding = view.gridPadding
        let fraction: CGFloat = type == .leftMouseDown ? 0.25 : 0.75
        let point = NSPoint(x: padding + (CGFloat(column) + fraction) * cell.width, y: view.bounds.height - padding - 0.5 * cell.height)
        return try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags, timestamp: time, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func aDragWithTheMouseSelectsTextAndTheViewDrawsIt() throws {
        let view = try makeView()
        view.mouseDown(with: try event(.leftMouseDown, column: 4, in: view))
        view.mouseDragged(with: try event(.leftMouseDragged, column: 6, in: view))
        view.mouseUp(with: try event(.leftMouseUp, column: 6, in: view))
        #expect(view.terminal.selectedText() == "two")
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view, [], at: 20))
        #expect(!view.terminal.hasSelection)
    }

    @Test func shiftSelectsEvenWhenTheProgramReadsTheMouse() throws {
        let view = try makeView("\u{1B}[?1002h\u{1B}[?1006h")
        view.mouseDown(with: try event(.leftMouseDown, column: 4, in: view, .shift))
        view.mouseDragged(with: try event(.leftMouseDragged, column: 6, in: view, .shift))
        #expect(view.terminal.selectedText() == "two")
        view.mouseUp(with: try event(.leftMouseUp, column: 6, in: view, .shift))
        view.mouseDown(with: try event(.leftMouseDown, column: 4, in: view, [], at: 20))
        view.mouseDragged(with: try event(.leftMouseDragged, column: 8, in: view, [], at: 20))
        #expect(view.terminal.selectedText() == "two")
    }
}
