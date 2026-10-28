import AppKit
import SessionProtocol
import Testing
import TerminalView
@testable import SessionWindow

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
}
