import AgentConversation
import Testing
@testable import CodexAgent

/// A stop right after the start of a turn, against the fake app-server.
@Suite struct CodexEndToEndStopTests {
    @Test func aStopBeforeTheStartOfTheTurnEndsTheTurn() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start", "stop-before-start"]))
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Count to a thousand."))
        // The fake app-server sends `turn/started` only after the interrupt.
        #expect(await thread.stop() == CodexStop(interruptedTurn: true))
        let events = await CodexFakeServer.events(of: thread) { if case .turnEnded = $0 { true } else { false } }
        #expect(events.last?.kind == .turnEnded(TurnEnd(outcome: .stopped, durationMilliseconds: 120)))
        await server.shutDown()
        #expect(await CodexFakeServer.events(of: thread).last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }
}
