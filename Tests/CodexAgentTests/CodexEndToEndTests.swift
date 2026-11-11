import AgentConversation
import Testing
@testable import CodexAgent

/// The client against the fake app-server, through `AgentProgram`.
@Suite struct CodexEndToEndTests {
    @Test func aTurnReachesATranscriptAndTheServerEndsCleanly() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start", "plain-turn"]))
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Reply with the single word ok."))
        var events = await CodexFakeServer.events(of: thread) { if case .turnEnded = $0 { true } else { false } }
        await server.shutDown()
        events += await CodexFakeServer.events(of: thread)
        let transcript = Transcript(events: events)
        #expect(transcript.items.contains { $0.content == .agentMessage(AgentMessage(text: "ok", isComplete: true)) })
        // The fake app-server ends with the status 0 only when every line
        // of OpenRun was the expected one.
        #expect(events.last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }

    @Test func aLineThatTheFixtureDoesNotExpectEndsTheFakeServer() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["second-thread"]))
        await #expect(throws: CodexRequestError.connectionEnded) {
            try await server.startThread(CodexThreadStart(folder: "/work/project"))
        }
        // The server learns the end after the process exit, a little later.
        while await !server.hasEnded { try await Task.sleep(for: .milliseconds(10)) }
    }
}
