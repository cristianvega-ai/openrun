import AppKit
import Metal
import SessionProtocol
import TerminalEmulation
import TerminalRendering
import Testing
@testable import SessionWindow
@testable import TerminalView

/// The size rules of 2026-10-24 and 2026-10-25, and the answer of the owner of 2026-10-27.
@MainActor @Suite struct WindowSizeFollowerTests {
    /// A window with its view, after the first layout, at the size of the snapshot.
    private func makeAttachedWindow() async throws -> (controller: SessionWindowController, attachment: FakeAttachment, view: TerminalView) {
        let attachment = try FakeAttachment(size: TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2))
        let controller = try makeWindowController(attachment)
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        return (controller, attachment, try #require(controller.view))
    }

    private func sessionSize(_ size: TerminalSize) -> SessionSize { SessionSize(columns: size.columns, rows: size.rows) }

    @Test func aSizeFromTheSessionGoesToTheViewWithNoAnswer() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        let own = try #require(view.visibleGridSize), larger = TerminalSize(columns: own.columns + 40, rows: own.rows + 20)
        attachment.deliver(.sizeChanged(sessionSize(larger)))
        await waitOnMainThread { view.gridSize == larger }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        await waitOnMainThread(seconds: 0.2) { false }
        #expect(view.gridSize == larger && view.visibleGridSize == own && attachment.record.withLock { $0.sizes }.isEmpty)
    }

    @Test func theWindowTakesItsSizeBackWhenItBecomesKeyAndOnlyThen() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        let own = try #require(view.visibleGridSize)
        attachment.deliver(.sizeChanged(SessionSize(columns: 30, rows: 8)))
        await waitOnMainThread { view.gridSize == TerminalSize(columns: 30, rows: 8) }
        #expect(attachment.record.withLock { $0.sizes }.isEmpty)
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        await waitOnMainThread { view.gridSize == own }
        #expect(attachment.record.withLock { $0.sizes } == [sessionSize(own)])
        #expect(attachment.record.withLock { $0.confirmationRequests } == [sessionSize(own)])
    }

    @Test func aQueuedForeignSizeCannotUndoTheKeyWindowTakeover() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        let own = try #require(view.visibleGridSize), foreign = TerminalSize(columns: 30, rows: 8)
        attachment.record.withLock { $0.confirmsSizes = false }
        attachment.deliver(.sizeChanged(sessionSize(foreign)))
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        await waitOnMainThread { view.gridSize == foreign && attachment.record.withLock { !$0.confirmationRequests.isEmpty } }
        #expect(view.gridSize == foreign && attachment.record.withLock { $0.sizes } == [sessionSize(own)])
        attachment.deliver(.sizeChanged(sessionSize(own)))
        await waitOnMainThread { view.gridSize == own }
        #expect(view.gridSize == own && attachment.record.withLock { $0.sizes } == [sessionSize(own)])
        #expect(attachment.record.withLock { $0.confirmationRequests } == [sessionSize(own)])
    }

    /// The alternate screen does not reflow, so a line shows the size it came for.
    @Test func outputBeforeASizeChangeKeepsTheOldSize() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        attachment.deliver(.output(Data(("\u{1B}[?1049h" + String(repeating: "x", count: 60)).utf8)))
        attachment.deliver(.sizeChanged(SessionSize(columns: 30, rows: 8)))
        await waitOnMainThread { view.gridSize == TerminalSize(columns: 30, rows: 8) }
        #expect(view.screenText == String(repeating: "x", count: 30))
    }

    @Test func aSmallerSessionGridStaysAtTheTopLeftAndFillsTheRest() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        attachment.deliver(.sizeChanged(SessionSize(columns: 10, rows: 3)))
        await waitOnMainThread { view.gridSize == TerminalSize(columns: 10, rows: 3) }
        view.terminal.write("\u{1B}[?25l█")
        let scale = view.renderer.fonts.scale
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()),
            width: Int((view.bounds.width * scale).rounded()), height: Int((view.bounds.height * scale).rounded()))
        #expect(try view.drawFrame(into: target))
        #expect(target.pixel(x: view.renderer.padding + view.renderer.fonts.cellWidth / 2,
                             y: view.renderer.padding + view.renderer.fonts.cellHeight / 2) == view.theme.foreground)
        #expect(target.pixel(x: target.texture.width - 1, y: target.texture.height - 1) == view.theme.background)
        #expect(controller.hiddenGridLabel.isHidden && attachment.record.withLock { $0.sizes }.isEmpty)
    }
}
