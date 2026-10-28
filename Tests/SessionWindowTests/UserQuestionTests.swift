import AppKit
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite struct UserQuestionTests {
    private final class Pasteboard: PasteboardAccess {
        var text: String? = "one\ntwo"
        func plainText() -> String? { text }
        func write(plainText: String) { text = plainText }
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
    }
}
