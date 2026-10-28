import AppKit
import Metal
import SessionProtocol
import SessionConnection
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

    @Test func theHiddenGridLabelWaitsUntilTheNewSizeApplies() async throws {
        let (controller, attachment, view) = try await makeAttachedWindow()
        defer { controller.window.close() }
        let own = try #require(view.visibleGridSize)
        let larger = TerminalSize(columns: own.columns + 40, rows: own.rows + 20)
        view.write([UInt8](repeating: 0, count: 2 * 1024 * 1024))
        view.followSessionSize(larger)
        #expect(view.gridSize == own && controller.hiddenGridLabel.isHidden)
        await waitOnMainThread(seconds: 10) { view.gridSize == larger }
        #expect(view.gridSize == larger && !controller.hiddenGridLabel.isHidden)
        #expect(attachment.record.withLock { $0.sizes.isEmpty })
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

    @Test func keyStatusDuringAttachControlsTheDeferredTakeover() async throws {
        try await checkKeyStatusDuringAttach(staysKey: true)
        try await checkKeyStatusDuringAttach(staysKey: false)
        try await checkKeyStatusDuringAttach(staysKey: false, reportsResign: false)
    }

    private func checkKeyStatusDuringAttach(staysKey: Bool, reportsResign: Bool = true) async throws {
        _ = NSApplication.shared
        let controller = SessionWindowController(start: .runningSession(UUID()), socket: try SocketLocation(path: "/tmp/openrun-window-test.socket"))
        let size = TerminalView.estimatedGrid(for: controller.window.contentLayoutRect.size, scale: controller.window.backingScaleFactor)
        let attachment = try FakeAttachment(size: size)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); controller.window.close() }
        controller.connect = { _, _, size in
            guard gate.wait(timeout: .now() + .seconds(20)) == .success else { throw SessionConnectionError.connectionClosed }
            return StartedSession(summary: SessionSummary(identifier: UUID(), folder: "/tmp", command: ["/bin/sh"], size: size, createdAt: Date()), attachment: attachment)
        }
        var isKey = false
        controller.isWindowKey = { _ in isKey }
        controller.showWindow()
        isKey = true
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        if !staysKey {
            isKey = false
            if reportsResign { controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification)) }
        }
        gate.signal()
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let visible = try #require(controller.view?.visibleGridSize)
        if staysKey { await waitOnMainThread { !attachment.record.withLock { $0.confirmationRequests }.isEmpty } }
        else { await waitOnMainThread(seconds: 0.2) { false } }
        #expect(attachment.record.withLock { $0.confirmationRequests } == (staysKey ? [sessionSize(visible)] : []))
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
        #expect(target.pixel(horizontalPosition: view.renderer.padding + view.renderer.fonts.cellWidth / 2,
                             verticalPosition: view.renderer.padding + view.renderer.fonts.cellHeight / 2) == view.theme.foreground)
        #expect(target.pixel(horizontalPosition: target.texture.width - 1, verticalPosition: target.texture.height - 1) == view.theme.background)
        #expect(controller.hiddenGridLabel.isHidden && attachment.record.withLock { $0.sizes }.isEmpty)
    }
}
