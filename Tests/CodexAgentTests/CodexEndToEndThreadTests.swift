import AgentConversation
import Testing
@testable import CodexAgent

/// A resumed thread against the fake app-server: a stop with a command
/// that runs on, and a turn with a model that the account cannot use.
@Suite struct CodexEndToEndThreadTests {
    let resumed = "00000000-0000-7000-8000-000000000013"

    @Test func aStopEndsTheCommandAndTheNextTurnWorks() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["resume", "interrupt", "unknown-model"]))
        let thread = try await server.resumeThread(identifier: resumed, CodexThreadStart(folder: "/work/project"))
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Run the command."))
        var stop: Task<CodexStop, Never>?
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if case .permissionRequested(let request) = event.kind {
                if request.identifier.hasSuffix("/0") { await thread.answerPermission(identifier: request.identifier, answer: .allow) }
                if request.identifier.hasSuffix("/1") { stop = Task { await thread.stop() } }
            }
            // The command that the stop ended completes after its turn.
            if case .agentStatus(let status) = event.kind, status.detail == "after the end of its turn", status.kind == "item/completed" { break }
        }
        #expect(await stop?.value == CodexStop(interruptedTurn: true, endedCommandCount: 1))
        #expect(Transcript(events: events).state == .idle)

        try await thread.startTurn(CodexTurn(messageIdentifier: "message-2", text: "Reply with the single word ok.", model: "no-such-model"))
        let failed = await CodexFakeServer.events(of: thread) { if case .agentStatus(let status) = $0 { status.kind == "turn/error" } else { false } }
        #expect(failed.dropLast().last?.kind == .turnEnded(TurnEnd(
            outcome: .failed, errorText: "The 'no-such-model' model is not supported when using Codex with a ChatGPT account.", durationMilliseconds: 5_790)))
        #expect(failed.last?.kind == .agentStatus(AgentStatus(kind: "turn/error", detail: "modelNotFound")))
        await server.shutDown()
        #expect(await CodexFakeServer.events(of: thread).last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }
}
