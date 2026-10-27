import AppKit
import Testing
@testable import TerminalView

@MainActor @Suite struct AutoscrollTests {
    @Test func aTimerRunsOnlyWhileTheDragAsksForAScroll() {
        let clock = ManualClock()
        var steps = 0
        let timer = SelectionAutoscrollTimer(clock: clock) { steps += 1 }
        timer.update(for: .up)
        timer.update(for: .down)
        clock.advance(by: .milliseconds(46))
        #expect(steps == 3)
        timer.update(for: .none)
        clock.advance(by: .milliseconds(100))
        #expect(steps == 3)
    }

    @Test func aDragAboveTheViewScrollsUpEvery15MillisecondsAndGrowsTheSelection() throws {
        let clock = ManualClock()
        let view = try TerminalView(clock: clock)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutSubtreeIfNeeded()
        view.terminal.write((1...200).map { "line \($0)\r\n" }.joined())
        func event(_ type: NSEvent.EventType, y: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 100, y: y), modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func firstRow() -> Int { Int(view.terminal.scrollbar.firstVisibleRow) }
        view.mouseDown(with: try event(.leftMouseDown, y: 200))
        view.mouseDragged(with: try event(.leftMouseDragged, y: 450))
        let start = firstRow()
        clock.advance(by: .milliseconds(46))
        #expect(firstRow() == start - 3)
        #expect(view.terminal.selectedText()?.contains("line") == true)
        view.mouseUp(with: try event(.leftMouseUp, y: 450))
        clock.advance(by: .milliseconds(100))
        #expect(firstRow() == start - 3)
    }
}
