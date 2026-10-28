import AppKit
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite struct SessionWindowControllerTests {
    @Test func theWindowAttachesWithTheGridOfItsViewAndDetachesWhenItCloses() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        let grid = TerminalView.estimatedGrid(for: controller.window.contentLayoutRect.size, scale: controller.window.backingScaleFactor)
        await waitOnMainThread { controller.attachment != nil }
        #expect(attachment.record.withLock { $0.attachSize } == SessionSize(columns: grid.columns, rows: grid.rows))
        controller.window.close()
        await waitOnMainThread { attachment.record.withLock { $0.shutDown } }
        #expect(attachment.record.withLock { $0.detached && $0.shutDown })
    }

    @Test func aWindowThatCannotAttachCloses() async throws {
        let controller = try makeWindowController(nil)
        await waitOnMainThread { !controller.window.isVisible }
        #expect(!controller.window.isVisible)
    }

    @Test func theWindowShowsTheSnapshotAndThenTheOutputInItsView() async throws {
        let attachment = try FakeAttachment(screen: "before\r\n")
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        #expect(controller.window.contentView === controller.view && controller.window.firstResponder === controller.view)
        attachment.deliver(.output(Data("after".utf8)))
        await waitOnMainThread { controller.view?.screenText.contains("after") == true }
        #expect(controller.view?.screenText == "before\nafter")
    }

    @Test func aSnapshotThatCannotBeRestoredDetachesAndClosesTheWindow() async throws {
        let attachment = FakeAttachment(snapshot: Data("not a snapshot".utf8))
        let controller = try makeWindowController(attachment)
        await waitOnMainThread { attachment.record.withLock { $0.shutDown } }
        #expect(!controller.window.isVisible && controller.view == nil && attachment.record.withLock { $0.detached })
    }

    @Test func keysGoToTheSessionInOrderAndNotFromTheMainThread() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view)
        for key in ["l", "s", "\r"] { controller.terminalView(view, send: Array(key.utf8)) }
        await waitOnMainThread { attachment.record.withLock { $0.inputs.count == 3 } }
        #expect(attachment.record.withLock { $0.inputs == ["l", "s", "\r"].map { Data($0.utf8) } && !$0.sentOnMainThread })
    }

    /// The window sends its size after the snapshot only when the sizes differ (decision of 2026-10-25).
    @Test(arguments: [true, false]) func theWindowSendsItsSizeAfterTheSnapshotWhenItDiffers(differs: Bool) async throws {
        let estimate = TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2)
        let attachment = try FakeAttachment(size: differs ? TerminalSize(columns: 50, rows: 10) : estimate)
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        try #require(attachment.record.withLock { $0.attachSize } == SessionSize(columns: estimate.columns, rows: estimate.rows))
        await waitOnMainThread { attachment.record.withLock { !$0.sizes.isEmpty } || !differs }
        await waitOnMainThread(seconds: 0.2) { false }
        let grid = try #require(controller.view?.gridSize)
        #expect(attachment.record.withLock { $0.sizes } == (differs ? [SessionSize(columns: grid.columns, rows: grid.rows)] : []))
    }
}
