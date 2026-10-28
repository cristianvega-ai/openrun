import AppKit
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite struct UserQuestionTests {
    private final class Pasteboard: PasteboardAccess {
        var text: String? = "one\ntwo"
        var hasPlainText: Bool { text != nil }
        func plainText() -> String? { text }
        func write(plainText: String) { text = plainText }
    }

    @Test func aLinkQuestionShowsTheFullAddressAndNeedsYes() async throws {
        let address = "file:///tmp/" + String(repeating: "long-path/", count: 80)
        let alert = UserQuestion.openLink(address).makeAlert()
        let scroll = try #require(alert.accessoryView as? NSScrollView)
        let text = try #require(scroll.documentView as? NSTextView)
        #expect(text.string == address && !text.isEditable && text.isSelectable && scroll.hasVerticalScroller)
        let container = try #require(text.textContainer)
        text.layoutManager?.ensureLayout(for: container)
        #expect(text.bounds.height > scroll.contentSize.height)
        #expect(UserQuestion.openLink(address).words.buttons == ["Open", "Cancel"])
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view)
        var questions: [UserQuestion] = []
        var answer: CheckedContinuation<Bool, Never>?
        controller.ask = { question, _ in
            questions.append(question)
            return await withCheckedContinuation { answer = $0 }
        }
        let first = Task { await controller.terminalView(view, shouldOpenLink: address) }
        await waitOnMainThread { answer != nil }
        let no = try #require(answer)
        answer = nil
        no.resume(returning: false)
        #expect(!(await first.value))
        let second = Task { await controller.terminalView(view, shouldOpenLink: address) }
        await waitOnMainThread { answer != nil }
        let yes = try #require(answer)
        answer = nil
        yes.resume(returning: true)
        #expect(await second.value)
        #expect(questions == [.openLink(address), .openLink(address)])
        let third = Task { await controller.terminalView(view, shouldOpenLink: address) }
        await waitOnMainThread { answer != nil }
        let tooLate = try #require(answer)
        controller.window.close()
        tooLate.resume(returning: true)
        #expect(!(await third.value))
    }

    @Test func anUnsafePasteWaitsForTheAnswerOfTheUser() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view), board = Pasteboard()
        view.pasteboard = board
        let expectedWindow = controller.window
        var questions: [UserQuestion] = []
        var answer: CheckedContinuation<Bool, Never>?
        controller.ask = { question, window in
            questions.append(question)
            #expect(window === expectedWindow)
            return await withCheckedContinuation { answer = $0 }
        }
        view.paste(nil)
        await waitOnMainThread { answer != nil }
        #expect(attachment.record.withLock { $0.inputs }.isEmpty)
        let first = try #require(answer)
        answer = nil
        first.resume(returning: false)
        await waitOnMainThread(seconds: 0.1) { false }
        #expect(attachment.record.withLock { $0.inputs }.isEmpty)
        view.paste(nil)
        await waitOnMainThread { answer != nil }
        #expect(attachment.record.withLock { $0.inputs }.isEmpty)
        let second = try #require(answer)
        answer = nil
        second.resume(returning: true)
        await waitOnMainThread { !attachment.record.withLock { $0.inputs }.isEmpty }
        #expect(attachment.record.withLock { $0.inputs } == [Data("one\rtwo".utf8)])
        #expect(questions == [.unsafePaste, .unsafePaste])
        #expect(UserQuestion.unsafePaste.words.buttons == ["Paste", "Cancel"])
        view.paste(nil)
        await waitOnMainThread { answer != nil }
        let third = try #require(answer)
        answer = nil
        controller.window.close()
        third.resume(returning: true)
        await waitOnMainThread(seconds: 0.1) { false }
        #expect(attachment.record.withLock { $0.inputs } == [Data("one\rtwo".utf8)])
    }
}
