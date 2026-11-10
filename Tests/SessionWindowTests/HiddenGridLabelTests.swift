import AppKit
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite struct HiddenGridLabelTests {
    private func text(_ grid: (UInt16, UInt16), visible: (UInt16, UInt16)) -> String? {
        HiddenGridLabel.text(grid: TerminalSize(columns: grid.0, rows: grid.1), visible: TerminalSize(columns: visible.0, rows: visible.1))
    }

    @Test func theLabelNamesTheHiddenRowsAndColumns() {
        #expect(text((80, 64), visible: (80, 24)) == "40 rows hidden")
        #expect(text((100, 24), visible: (80, 24)) == "20 columns hidden")
        #expect(text((81, 25), visible: (80, 24)) == "1 row and 1 column hidden")
        #expect(text((60, 20), visible: (80, 24)) == nil)
    }

    @Test func theWindowShowsTheLabelForALargerGridOfTheSessionUntilItTakesItsSizeBack() async throws {
        let attachment = try FakeAttachment(size: TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2))
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let own = try #require(controller.view?.visibleGridSize)
        #expect(controller.hiddenGridLabel.isHidden && controller.hiddenGridLabel.superview === controller.window.contentView)
        attachment.deliver(.sizeChanged(SessionSize(columns: own.columns, rows: own.rows + 40)))
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        #expect(controller.hiddenGridLabel.stringValue == "40 rows hidden")
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        await waitOnMainThread { controller.hiddenGridLabel.isHidden }
        #expect(controller.hiddenGridLabel.isHidden)
    }

    @Test func theLabelClearsWhenTheViewGrowsToTheSizeOfTheSession() async throws {
        let attachment = try FakeAttachment(size: TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2))
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let view = try #require(controller.view), own = try #require(view.visibleGridSize)
        let larger = TerminalSize(columns: own.columns + 2, rows: own.rows + 3)
        attachment.deliver(.sizeChanged(SessionSize(columns: larger.columns, rows: larger.rows)))
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        view.frame.size = NSSize(width: CGFloat(larger.columns) * view.cellSize.width + 2 * view.gridPadding + 0.5,
                                 height: CGFloat(larger.rows) * view.cellSize.height + 2 * view.gridPadding + 0.5)
        view.layout()
        #expect(view.visibleGridSize == larger && view.gridSize == larger && controller.hiddenGridLabel.isHidden)
        await waitOnMainThread { !attachment.record.withLock { $0.confirmationRequests }.isEmpty }
        #expect(attachment.record.withLock { $0.confirmationRequests } == [SessionSize(columns: larger.columns, rows: larger.rows)])
    }

    /// During a drag, the session confirms an older size of the window while
    /// a newer one still waits. That older size is no grid of another client.
    @Test func theConfirmationOfAnOlderRequestShowsNoLabel() async throws {
        let attachment = try FakeAttachment(size: TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2))
        attachment.record.withLock { $0.confirmsSizes = false }
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let view = try #require(controller.view), own = try #require(view.visibleGridSize)
        let older = TerminalSize(columns: own.columns + 7, rows: own.rows)
        controller.terminalView(view, didChangeGridSize: older)
        controller.terminalView(view, didChangeGridSize: own)
        attachment.deliver(.sizeChanged(SessionSize(columns: older.columns, rows: older.rows)))
        await waitOnMainThread { view.gridSize == older }
        #expect(controller.hiddenGridLabel.isHidden)
        attachment.deliver(.sizeChanged(SessionSize(columns: own.columns, rows: own.rows + 5)))
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        #expect(controller.hiddenGridLabel.stringValue == "5 rows hidden")
    }

    @Test func aSizeThatArrivesAsReceivingStartsFollowsTheFirstLayout() async throws {
        let own = TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2)
        let larger = SessionSize(columns: own.columns + 1, rows: own.rows + 2)
        let attachment = try FakeAttachment(size: own, earlyEvent: .sizeChanged(larger))
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        #expect(controller.view?.visibleGridSize == own)
        #expect(controller.hiddenGridLabel.stringValue == "2 rows and 1 column hidden")
        #expect(attachment.record.withLock { $0.sizes }.isEmpty)
    }
}
