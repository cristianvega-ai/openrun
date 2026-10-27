import AppKit
import CoreGraphics
import TerminalEmulation
import Testing
@testable import TerminalView

@Suite struct ScrollAccumulatorTests {
    @Test func aTurnOfAWheelMovesThreeRowsAndASlowTurnMovesOneTurn() {
        var accumulator = ScrollAccumulator()
        func add(_ delta: CGFloat) -> ScrollAccumulator.Step {
            accumulator.add(delta: delta, isPrecise: false, startsGesture: false, cellHeight: 15.5)
        }
        #expect(add(1) == .init(rows: 3, ticks: 1))
        #expect(add(-1) == .init(rows: -3, ticks: -1))
        #expect(add(0.2) == .init(rows: 3, ticks: 1))
        #expect(add(-0.2) == .init(rows: -3, ticks: -1))
        #expect(add(5) == .init(rows: 15, ticks: 5))
        #expect(add(0) == .init(rows: 0, ticks: 0))
    }

    @Test func aTrackpadAddsPointsUntilTheyMakeARowAndKeepsTheRest() {
        var accumulator = ScrollAccumulator()
        func add(_ delta: CGFloat, starts: Bool = false) -> Int {
            accumulator.add(delta: delta, isPrecise: true, startsGesture: starts, cellHeight: 10).rows
        }
        #expect([add(4), add(4), add(4), add(4), add(4)] as [Int] == [0, 0, 1, 0, 1])
        #expect(add(-25) == -2)
        #expect([add(-4), add(-1)] as [Int] == [0, -1])
    }

    @Test func aNewGestureForgetsTheRestOfTheLastOne() {
        var accumulator = ScrollAccumulator()
        _ = accumulator.add(delta: 9, isPrecise: true, startsGesture: false, cellHeight: 10)
        #expect(accumulator.add(delta: 2, isPrecise: true, startsGesture: false, cellHeight: 10).rows == 1)
        _ = accumulator.add(delta: 9, isPrecise: true, startsGesture: false, cellHeight: 10)
        #expect(accumulator.add(delta: 2, isPrecise: true, startsGesture: true, cellHeight: 10).rows == 0)
    }
}

@MainActor @Suite struct ScrollInputTests {
    private func action(_ output: String, delta: CGFloat, isPrecise: Bool = false) throws -> ScrollInput.Action? {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 5), scrollbackLimit: 100)
        terminal.write(output)
        return ScrollInput().action(delta: delta, isPrecise: isPrecise, startsGesture: false, cellHeight: 10, terminal: terminal)
    }

    @Test func theWheelMovesTheViewportOnThePrimaryScreen() throws {
        #expect(try action("", delta: 1) == .viewport(rows: -3))
        #expect(try action("", delta: -2) == .viewport(rows: 6))
        #expect(try action("", delta: 14, isPrecise: true) == .viewport(rows: -1))
        #expect(try action("", delta: 4, isPrecise: true) == nil)
    }

    @Test func aProgramWithMouseReportsGetsOneReportForEachTurn() throws {
        #expect(try action("\u{1B}[?1000h", delta: 2) == .wheelReports(button: .wheelUp, count: 2))
        #expect(try action("\u{1B}[?1000h\u{1B}[?1049h", delta: -1) == .wheelReports(button: .wheelDown, count: 1))
        #expect(try action("\u{1B}[?1000h", delta: 25, isPrecise: true) == .wheelReports(button: .wheelUp, count: 2))
    }

    @Test func theAlternateScreenGetsArrowKeysWhileMode1007IsOn() throws {
        #expect(try action("\u{1B}[?1049h", delta: 1) == .arrowKeys(up: true, count: 3))
        #expect(try action("\u{1B}[?1049h", delta: -2) == .arrowKeys(up: false, count: 6))
        #expect(try action("\u{1B}[?1049h\u{1B}[?1007l", delta: 1) == nil)
    }
}

@MainActor @Suite struct ScrollOfViewTests {
    private func makeView(_ output: String = "") throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.terminal.write(String(repeating: "line\r\n", count: 100) + output)
        return (view, delegate)
    }

    /// A scroll event of the wheel (`pixels` is `false`) or of a trackpad, with the phases of AppKit.
    private func scroll(_ amount: Int32, pixels: Bool = false, phase: Int64 = 0, momentum: Int64 = 0) throws -> NSEvent {
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: pixels ? .pixel : .line, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return try #require(NSEvent(cgEvent: cgEvent))
    }

    @Test func aWheelTurnMovesThreeRowsAndATrackpadMovesByTheHeightOfARow() throws {
        let (view, _) = try makeView()
        func row() -> Int { Int(view.terminal.scrollbar.firstVisibleRow) }
        let bottom = row()
        view.scrollWheel(with: try scroll(1))
        #expect(row() == bottom - 3 && !view.terminal.isViewportAtBottom)
        let height = Int32(view.cellSize.height.rounded(.up))
        view.scrollWheel(with: try scroll(-height / 2, pixels: true, phase: 1))
        #expect(row() == bottom - 3)
        view.scrollWheel(with: try scroll(-height, pixels: true, phase: 2))
        #expect(row() == bottom - 2)
        view.scrollWheel(with: try scroll(-height, pixels: true, momentum: 2))
        #expect(row() == bottom - 1)
    }

    @Test func aProgramGetsWheelReportsOrArrowKeys() throws {
        let (reporting, reports) = try makeView("\u{1B}[?1000h\u{1B}[?1006h")
        reporting.scrollWheel(with: try scroll(2))
        // The event has no window, so the place of the report is not the point of the test.
        let sent = reports.takeSent()
        #expect(sent.hasPrefix("\u{1B}[<64;") && sent.filter { $0 == "M" }.count == 2)
        let (full, keys) = try makeView("\u{1B}[?1049h")
        full.scrollWheel(with: try scroll(-1))
        #expect(keys.takeSent() == String(repeating: "\u{1B}[B", count: 3))
    }
}
