import AppKit
import CoreGraphics
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct MouseReporterTests {
    /// 80 by 24 cells of 8 by 15.5 points, with 8 points of padding, on a screen with scale 2.
    private let location = PointerLocation(cellSize: CGSize(width: 8, height: 15.5), padding: 8, scale: 2, gridSize: TerminalSize(columns: 80, rows: 24), viewHeight: 388)

    private func cellPoint(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: 8 + 8 * CGFloat(column) + 3, y: 388 - (8 + 15.5 * CGFloat(row) + 4))
    }

    private func bytes(_ reporter: MouseReporter, _ action: MouseEvent.Action, _ button: MouseEvent.Button?, _ column: Int, _ row: Int) -> String {
        String(decoding: reporter.bytes(action, button: button, modifiers: [], at: cellPoint(column, row), in: location), as: UTF8.self)
    }

    @Test func aProgramGetsReportsOnlyWhenItAsksForThem() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 0)
        let reporter = try MouseReporter(terminal: terminal)
        #expect(!reporter.isActive && bytes(reporter, .press, .left, 5, 3) == "")
        terminal.write("\u{1B}[?1002h\u{1B}[?1006h")
        #expect(bytes(reporter, .press, .left, 5, 3) == "\u{1B}[<0;6;4M")
        #expect(bytes(reporter, .motion, .left, 6, 3) == "\u{1B}[<32;7;4M")
        #expect(bytes(reporter, .release, .left, 6, 3) == "\u{1B}[<0;7;4m")
        #expect(bytes(reporter, .press, .forward, 1, 1) == "\u{1B}[<129;2;2M")
        #expect(bytes(reporter, .press, .wheelUp, 0, 0) == "\u{1B}[<64;1;1M")
    }

    @Test func theEncoderReadsTheModesAgainOnlyWhenTheyChange() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 0)
        terminal.write("\u{1B}[?1003h\u{1B}[?1006h")
        let reporter = try MouseReporter(terminal: terminal)
        #expect(bytes(reporter, .motion, nil, 5, 3) == "\u{1B}[<35;6;4M")
        #expect(bytes(reporter, .motion, nil, 5, 3) == "")
        terminal.write("\u{1B}[?1006l")
        #expect(bytes(reporter, .motion, nil, 5, 3) == "\u{1B}[MC&$")
    }
}

@MainActor @Suite struct PointerInputTests {
    private let location = PointerLocation(cellSize: CGSize(width: 8, height: 15.5), padding: 8, scale: 2, gridSize: TerminalSize(columns: 80, rows: 24), viewHeight: 388)
    private let point = CGPoint(x: 51, y: 329.5)

    private func makePointer(_ output: String) throws -> PointerInput {
        let terminal = try Terminal(size: TerminalSize(columns: 80, rows: 24), scrollbackLimit: 0)
        terminal.write(output)
        return try PointerInput(terminal: terminal)
    }

    private func text(_ bytes: [UInt8]?) -> String? { bytes.map { String(decoding: $0, as: UTF8.self) } }

    @Test func aButtonThatWentDownForTheProgramStaysWithTheProgram() throws {
        let input = try makePointer("\u{1B}[?1002h\u{1B}[?1006h")
        #expect(text(input.bytes(.press, button: .left, modifiers: [], at: point, in: location)) == "\u{1B}[<0;6;4M")
        #expect(text(input.bytes(.motion, button: .left, modifiers: .shift, at: point, in: location)) == "")
        #expect(text(input.bytes(.release, button: .left, modifiers: .shift, at: point, in: location)) == "\u{1B}[<4;6;4m")
        #expect(input.bytes(.release, button: .left, modifiers: [], at: point, in: location) == nil)
    }

    @Test func shiftAndAProgramWithoutReportsKeepTheMouseForTheView() throws {
        let input = try makePointer("\u{1B}[?1003h\u{1B}[?1006h")
        #expect(input.bytes(.press, button: .left, modifiers: .shift, at: point, in: location) == nil)
        #expect(input.bytes(.motion, button: .left, modifiers: .shift, at: point, in: location) == nil)
        #expect(input.bytes(.motion, button: nil, modifiers: .shift, at: point, in: location) == nil)
        #expect(text(input.bytes(.motion, button: nil, modifiers: [], at: point, in: location)) == "\u{1B}[<35;6;4M")
        #expect(try makePointer("").bytes(.press, button: .left, modifiers: [], at: point, in: location) == nil)
    }

    @Test func appKitNumbersTheButtonsFromTheLeftOne() {
        let buttons = (0...5).map(PointerInput.button(forNumber:))
        #expect(buttons == [.left, .right, .middle, .back, .forward, nil])
    }
}

@MainActor @Suite struct MouseOfViewTests {
    private func makeView(_ output: String) throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutSubtreeIfNeeded()
        view.terminal.write(output)
        return (view, delegate)
    }

    /// A mouse event in the middle of the cell in column 5 and row 3.
    private func event(_ type: NSEvent.EventType, in view: TerminalView, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let cell = view.cellSize, padding = view.gridPadding
        let point = NSPoint(x: padding + 5.5 * cell.width, y: view.bounds.height - padding - 3.5 * cell.height)
        return try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags, timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func aProgramThatAsksForReportsGetsTheButtonsAndTheMotion() throws {
        let (view, delegate) = try makeView("\u{1B}[?1003h\u{1B}[?1006h")
        view.mouseMoved(with: try event(.mouseMoved, in: view))
        view.mouseDown(with: try event(.leftMouseDown, in: view))
        view.mouseUp(with: try event(.leftMouseUp, in: view))
        view.rightMouseDown(with: try event(.rightMouseDown, in: view))
        view.rightMouseUp(with: try event(.rightMouseUp, in: view))
        #expect(delegate.takeSent() == "\u{1B}[<35;6;4M\u{1B}[<0;6;4M\u{1B}[<0;6;4m\u{1B}[<2;6;4M\u{1B}[<2;6;4m")
    }

    @Test func aProgramWithoutReportsAndAShiftPressGetNothing() throws {
        let (plain, plainDelegate) = try makeView("")
        plain.mouseDown(with: try event(.leftMouseDown, in: plain))
        let (shifted, shiftedDelegate) = try makeView("\u{1B}[?1002h\u{1B}[?1006h")
        shifted.mouseDown(with: try event(.leftMouseDown, in: shifted, .shift))
        shifted.mouseDragged(with: try event(.leftMouseDragged, in: shifted, .shift))
        shifted.mouseUp(with: try event(.leftMouseUp, in: shifted, .shift))
        #expect(plainDelegate.takeSent() == "" && shiftedDelegate.takeSent() == "")
    }
}
