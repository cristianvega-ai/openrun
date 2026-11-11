import AgentConversation
import Darwin
import Testing
@testable import CodexAgent

/// The special cases of the fake app-server: no answer, a cut line, and
/// a crash.
@Suite struct CodexEndToEndFailureTests {
    @Test func anAnswerThatNeverComesFailsAfterTheTimeLimit() async throws {
        let options = CodexServerOptions(answerTimeLimit: .milliseconds(300))
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["never-answers"]), options: options)
        await #expect(throws: CodexRequestError.timedOut(method: "thread/start")) {
            try await server.startThread(CodexThreadStart(folder: "/work/project"))
        }
        await server.shutDown()
    }

    func turnThatFails(_ fixture: String) async throws -> [ConversationEvent] {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start", fixture]))
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Reply with the single word ok."))
        return await CodexFakeServer.events(of: thread)
    }

    @Test func outputCutInALineGivesTheStartOfTheLineAndTheEnd() async throws {
        let events = try await turnThatFails("cut-line")
        guard case .unknown(let line)? = events.dropLast().last?.kind else { Issue.record("No cut line"); return }
        #expect(line.reason == .cutShort)
        #expect(line.text.contains(#""method":"turn/started""#))
        guard case .processEnded(let end)? = events.last?.kind else { Issue.record("No end"); return }
        #expect(end.exitStatus == 1)
        #expect(end.isFailure)
    }

    @Test func aCrashEndsTheThreadWithTheSignal() async throws {
        let events = try await turnThatFails("crash")
        guard case .processEnded(let end)? = events.last?.kind else { Issue.record("No end"); return }
        #expect(end.signal == SIGKILL)
        #expect(!end.wasRequested)
    }
}
