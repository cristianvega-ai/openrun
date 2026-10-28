import AppKit
import SessionProtocol
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
}
