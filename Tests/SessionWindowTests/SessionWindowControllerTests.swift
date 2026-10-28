import AppKit
import SessionConnection
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

    @Test func anAttachFailureIsShownBeforeTheWindowCloses() async throws {
        let controller = try makeWindowController(nil)
        var questions: [UserQuestion] = []
        var answer: CheckedContinuation<Bool, Never>?
        controller.ask = { question, _ in
            questions.append(question)
            return await withCheckedContinuation { answer = $0 }
        }
        await waitOnMainThread { answer != nil }
        #expect(controller.window.isVisible)
        #expect(questions == [.connectionFailure("Could not connect to the session. The session process closed the connection.")])
        let acknowledgment = try #require(answer)
        acknowledgment.resume(returning: true)
        await waitOnMainThread { !controller.window.isVisible }
        #expect(!controller.window.isVisible)
    }

    @Test func theWindowShowsTheSnapshotAndThenTheOutputInItsView() async throws {
        let attachment = try FakeAttachment(screen: "before\r\n")
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        #expect(controller.view?.superview === controller.window.contentView && controller.window.firstResponder === controller.view)
        attachment.deliver(.output(Data("after".utf8)))
        await waitOnMainThread { controller.view?.screenText.contains("after") == true }
        #expect(controller.view?.screenText == "before\nafter")
    }

    @Test func aSnapshotThatCannotBeRestoredDetachesAndClosesTheWindow() async throws {
        let attachment = FakeAttachment(snapshot: Data("not a snapshot".utf8))
        let controller = try makeWindowController(attachment)
        var questions: [UserQuestion] = []
        controller.ask = { question, _ in questions.append(question); return true }
        await waitOnMainThread { !controller.window.isVisible && attachment.record.withLock { $0.shutDown } }
        #expect(controller.view == nil && attachment.record.withLock { $0.detached })
        let question = try #require(questions.first)
        guard case .connectionFailure(let detail) = question else { Issue.record("Expected a connection failure"); return }
        #expect(detail.contains("could not be restored"))
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

    @Test func theWindowShowsTheProgramTitleAndTheFolderWhenItIsEmpty() async throws {
        let attachment = try FakeAttachment(screen: "\u{1B}]2;Initial title\u{07}")
        let controller = try makeWindowController(attachment, folder: "/tmp/project")
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        #expect(controller.window.title == "Initial title")
        attachment.deliver(.output(Data("\u{1B}]2;Later title\u{07}".utf8)))
        await waitOnMainThread { controller.window.title == "Later title" }
        #expect(controller.window.title == "Later title")
        attachment.deliver(.output(Data("\u{1B}]2;\u{07}".utf8)))
        await waitOnMainThread { controller.window.title == "/tmp/project" }
        #expect(controller.window.title == "/tmp/project")
    }

    @Test func aSnapshotWithoutATitleStartsWithTheFolder() async throws {
        let controller = try makeWindowController(FakeAttachment(), folder: "/tmp/project")
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        #expect(controller.window.title == "/tmp/project")
    }
    @Test func theWindowClosesWhenTheProgramEndsAndReportsTheCloseOnce() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        var closeCount = 0
        controller.onClose = { closeCount += 1 }
        await waitOnMainThread { controller.view != nil }
        attachment.deliver(.exited(.exited(status: 0)))
        await waitOnMainThread { closeCount == 1 }
        #expect(!controller.window.isVisible && closeCount == 1)
        await waitOnMainThread { attachment.record.withLock { $0.shutDown } }
        #expect(attachment.record.withLock { $0.detached && $0.shutDown })
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(closeCount == 1)
    }

    @Test(arguments: ["receive", "input", "size"])
    func aLostConnectionOrAWriteErrorIsShownOnce(source: String) async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view)
        var questions: [UserQuestion] = []
        var answer: CheckedContinuation<Bool, Never>?
        controller.ask = { question, _ in
            questions.append(question)
            return await withCheckedContinuation { answer = $0 }
        }
        switch source {
        case "input":
            attachment.record.withLock { $0.failsInput = true }
            controller.terminalView(view, send: [65])
        case "size":
            attachment.record.withLock { $0.failsSize = true }
            controller.terminalView(view, didChangeGridSize: TerminalSize(columns: 40, rows: 10))
        default:
            attachment.deliver(.failed(.connectionClosed))
        }
        await waitOnMainThread { answer != nil }
        attachment.deliver(.closed)
        await waitOnMainThread(seconds: 0.1) { false }
        #expect(questions == [.connectionFailure("The session connection failed. The session process closed the connection.")])
        let acknowledgment = try #require(answer)
        acknowledgment.resume(returning: true)
        await waitOnMainThread { !controller.window.isVisible }
        #expect(!controller.window.isVisible)
    }

    @Test func anUnexpectedCloseIsShownToTheUser() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        var questions: [UserQuestion] = []
        controller.ask = { question, _ in questions.append(question); return true }
        await waitOnMainThread { controller.view != nil }
        attachment.deliver(.closed)
        await waitOnMainThread { !controller.window.isVisible }
        #expect(questions == [.connectionFailure("The session process closed the connection.")])
    }
}
