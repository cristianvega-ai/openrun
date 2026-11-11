import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerStopTests {
    @Test func aCodexWithoutTheExperimentalMethodsStillStopsAndSaysSo() async throws {
        let harness = try await CodexServerHarness()
        let channel = await harness.server.open("a", first: [])
        let stop = Task { await harness.server.stop(thread: "a") }
        let list = await harness.nextWritten()
        #expect(list?["method"] == .string("thread/backgroundTerminals/list"))
        harness.serve(#"{"id":\#(list?["id"]?.integer ?? 0),"error":{"code":-32601,"message":"unknown method"}}"#)
        #expect(await stop.value == CodexStop(commandsMayStillRun: true))
        #expect(await channel.next()?.kind == .notice(Notice(
            level: .warning, text: "OpenRun could not end the commands of the thread, so a command may still run.")))
    }

    @Test func aStopInterruptsTheTurnAndEndsItsCommand() async throws {
        let harness = try await CodexServerHarness()
        async let resumed = harness.play("resume")
        let thread = try await harness.server.resumeThread(identifier: "00000000-0000-7000-8000-000000000013", CodexThreadStart(folder: "/work/project"))
        _ = try await resumed
        async let played = harness.play("interrupt")
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Run the command."))
        var events: [ConversationEvent] = []
        var stop: Task<CodexStop, Never>?
        for await event in thread.events {
            events.append(event)
            if case .permissionRequested(let request) = event.kind {
                if request.identifier.hasSuffix("/0") { await thread.answerPermission(identifier: request.identifier, answer: .allow) }
                if request.identifier.hasSuffix("/1") { stop = Task { await thread.stop() } }
            }
            // The command that the stop ended completes after its turn.
            if case .agentStatus(let status) = event.kind, status.detail == "after the end of its turn", status.kind == "item/completed" { break }
        }
        _ = try await played
        #expect(await stop?.value == CodexStop(interruptedTurn: true, endedCommandCount: 1))
        #expect(events.contains { if case .permissionEnded(let end) = $0.kind { end.outcome == .cancelled } else { false } })
        #expect(events.contains { if case .turnEnded(let end) = $0.kind { end.outcome == .stopped } else { false } })
        #expect(Transcript(events: events).state == .idle)
    }
}
