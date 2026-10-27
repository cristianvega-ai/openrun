import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct OverlayScrollBarTests {
    /// The scroll bar values of a terminal with 20 rows, after `lines` lines of output.
    private func scrollbar(lines: Int, scrolledTo row: ViewportScroll? = nil) throws -> Scrollbar {
        let terminal = try Terminal(size: TerminalSize(columns: 10, rows: 20), scrollbackLimit: 1000)
        terminal.write(String(repeating: "x\r\n", count: lines))
        if let row { terminal.scrollViewport(row) }
        return terminal.scrollbar
    }

    @Test func theKnobShowsTheVisibleRowsAmongAllRowsAndTheBarIsHiddenWithoutScrollback() throws {
        let bar = OverlayScrollBar(clock: ManualClock())
        let middle = try scrollbar(lines: 80, scrolledTo: .toRow(40))
        bar.update(from: middle)
        #expect(!bar.isHidden && bar.scroller.scrollerStyle == .overlay)
        #expect(abs(bar.scroller.knobProportion - CGFloat(middle.visibleRows) / CGFloat(middle.totalRows)) < 0.0001)
        #expect(abs(bar.scroller.doubleValue - 40 / Double(middle.totalRows - middle.visibleRows)) < 0.0001)
        bar.update(from: try scrollbar(lines: 80, scrolledTo: .toTop))
        #expect(bar.scroller.doubleValue == 0)
        bar.update(from: try scrollbar(lines: 80))
        #expect(abs(bar.scroller.doubleValue - 1) < 0.0001)
        bar.update(from: try scrollbar(lines: 3))
        #expect(bar.isHidden)
    }

    @Test func theViewKeepsTheKnobAtThePlaceOfItsViewport() throws {
        let view = try TerminalView(initialGrid: TerminalSize(columns: 20, rows: 10))
        view.updateScrollBar()
        #expect(view.scrollBar.isHidden)
        view.terminal.write(String(repeating: "line\r\n", count: 90))
        view.updateScrollBar()
        #expect(!view.scrollBar.isHidden && abs(view.scrollBar.scroller.doubleValue - 1) < 0.0001)
        view.terminal.scrollViewport(.toTop)
        view.updateScrollBar()
        #expect(view.scrollBar.scroller.doubleValue == 0 && abs(view.scrollBar.scroller.knobProportion - 0.1) < 0.01)
    }

    @Test func theBarIsRevealedWhenTheUserScrollsAndTakesNoEventAfterOneSecond() throws {
        let clock = ManualClock()
        let view = try TerminalView(initialGrid: TerminalSize(columns: 20, rows: 10), clock: clock)
        view.terminal.write(String(repeating: "line\r\n", count: 90))
        view.updateScrollBar()
        let point = NSPoint(x: 1, y: 1)
        #expect(!view.scrollBar.isRevealed && view.scrollBar.hitTest(point) == nil)
        view.scrollWheel(with: try scrollEvent())
        #expect(view.scrollBar.isRevealed && view.scrollBar.hitTest(point) != nil)
        clock.advance(by: .milliseconds(800))
        view.scrollWheel(with: try scrollEvent())
        clock.advance(by: .milliseconds(800))
        #expect(view.scrollBar.isRevealed)
        clock.advance(by: .milliseconds(300))
        #expect(!view.scrollBar.isRevealed && view.scrollBar.hitTest(point) == nil)
    }

    private func scrollEvent() throws -> NSEvent {
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        return try #require(NSEvent(cgEvent: cgEvent))
    }
}
