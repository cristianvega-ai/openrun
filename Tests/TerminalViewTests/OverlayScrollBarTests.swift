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
        let event = try scrollEvent()
        try #require(event.scrollingDeltaY != 0)
        let bottom = view.terminal.scrollbar.firstVisibleRow
        view.scrollWheel(with: event)
        #expect(view.terminal.scrollbar.firstVisibleRow < bottom)
        #expect(view.scrollBar.isRevealed && view.scrollBar.hitTest(point) != nil)
        clock.advance(by: .milliseconds(800))
        let row = view.terminal.scrollbar.firstVisibleRow
        view.scrollWheel(with: event)
        #expect(view.terminal.scrollbar.firstVisibleRow < row)
        clock.advance(by: .milliseconds(800))
        #expect(view.scrollBar.isRevealed)
        clock.advance(by: .milliseconds(300))
        #expect(!view.scrollBar.isRevealed && view.scrollBar.hitTest(point) == nil)
    }

    private func scrollEvent() throws -> NSEvent {
        let graphicsEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        return try #require(NSEvent(cgEvent: graphicsEvent))
    }

    /// Moves the clip view of a bar, as the scroll view does when the user drags the knob.
    private func dragKnob(of bar: OverlayScrollBar, toRow row: Int, of scrollbar: Scrollbar) {
        let clip = bar.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: bar.bounds.height / CGFloat(scrollbar.visibleRows) * CGFloat(row)))
        bar.scrollView.reflectScrolledClipView(clip)
    }

    @Test func aDragOfTheKnobGivesTheRowToTheOwnerButAnUpdateDoesNot() throws {
        let bar = OverlayScrollBar(clock: ManualClock())
        var received: [ViewportScroll] = []
        bar.onScroll = { received.append($0) }
        let all = try scrollbar(lines: 80)
        bar.update(from: all)
        #expect(received.isEmpty)
        dragKnob(of: bar, toRow: 40, of: all)
        #expect(received == [.toRow(40)] && bar.isRevealed)
    }

    @Test func aDragOfTheKnobScrollsTheViewToARow() throws {
        let view = try TerminalView(initialGrid: TerminalSize(columns: 20, rows: 10), clock: ManualClock())
        view.terminal.write(String(repeating: "line\r\n", count: 90))
        view.updateScrollBar()
        let all = view.terminal.scrollbar
        dragKnob(of: view.scrollBar, toRow: 0, of: all)
        #expect(view.terminal.scrollbar.firstVisibleRow == 0)
        dragKnob(of: view.scrollBar, toRow: Int(all.totalRows - all.visibleRows), of: all)
        #expect(view.terminal.isViewportAtBottom)
    }

    @Test func aTallerBarDoesNotScrollTheView() throws {
        let bar = OverlayScrollBar(clock: ManualClock())
        var received: [ViewportScroll] = []
        bar.onScroll = { received.append($0) }
        let atBottom = try scrollbar(lines: 80)
        bar.update(from: atBottom)
        // A window resize sets the frame first, and the next frame calls `update` again.
        bar.frame = NSRect(x: 0, y: 0, width: bar.frame.width, height: 200)
        #expect(received.isEmpty)
        bar.update(from: atBottom)
        #expect(received.isEmpty)
        // A real drag still works with the new geometry.
        dragKnob(of: bar, toRow: 40, of: atBottom)
        #expect(received == [.toRow(40)])
    }

    @Test func aShorterBarKeepsTheRowThatTheReaderSees() throws {
        let bar = OverlayScrollBar(clock: ManualClock())
        var received: [ViewportScroll] = []
        bar.onScroll = { received.append($0) }
        let reading = try scrollbar(lines: 80, scrolledTo: .toRow(40))
        bar.frame = NSRect(x: 0, y: 0, width: bar.frame.width, height: 200)
        bar.update(from: reading)
        bar.frame = NSRect(x: 0, y: 0, width: bar.frame.width, height: 100)
        bar.update(from: reading)
        #expect(received.isEmpty)
    }

    /// Run with `OPENRUN_RENDER_OUTPUT=<folder>` to save a screenshot of a window with the scroll bar for a review.
    /// `screencapture` takes the window from the screen, because the knob of the overlay style is not in a bitmap of the view.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] != nil && NSScreen.main != nil))
    func theScreenshotOfAWindowWithTheScrollBar() throws {
        let folder = ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] ?? ""
        let view = try TerminalView(initialGrid: TerminalSize(columns: 50, rows: 10))
        let window = show(view)
        defer { window.close() }
        window.setContentSize(NSSize(width: 420, height: 170))
        window.makeKeyAndOrderFront(nil)
        view.write(Array((1...100).map { "line \($0) of the scrollback\r\n" }.joined().utf8))
        wait(seconds: 3) { view.framesDrawn > 0 }
        view.scrollWheel(with: try scrollEvent())
        wait(seconds: 0.4) { false }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", "\(folder)/scroll-bar.png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}
