import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerRoutingTests {
    func delta(_ thread: String, _ text: String) -> String {
        #"{"method":"item/agentMessage/delta","params":{"threadId":"\#(thread)","itemId":"m","delta":"\#(text)"}}"#
    }

    @Test func eachNotificationGoesToItsThreadAndTheAccountToEveryThread() async throws {
        let harness = try await CodexServerHarness()
        let first = await harness.server.open("a", first: [])
        let second = await harness.server.open("b", first: [])
        harness.serve(delta("a", "for a"))
        harness.serve(delta("b", "for b"))
        harness.serve(#"{"method":"account/rateLimits/updated","params":{"rateLimits":{}}}"#)
        harness.serve(#"{"method":"no/such/method","params":{"threadId":"a"}}"#)
        #expect(await first.next()?.kind == .agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "for a")))
        #expect(await second.next()?.kind == .agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "for b")))
        #expect(await first.next()?.kind == .usage(CodexUsage.reading(from: .object([:]))))
        #expect(await second.next()?.kind == .usage(CodexUsage.reading(from: .object([:]))))
        guard case .unknown(let line) = await first.next()?.kind else { Issue.record("No unknown event"); return }
        #expect(line.kind == "no/such/method")
    }

    @Test func aLineBeforeTheOpenOfItsThreadComesAfterTheFirstEvents() async throws {
        let harness = try await CodexServerHarness()
        let other = await harness.server.open("other", first: [])
        harness.serve(delta("early", "first"))
        harness.serve(delta("other", "mark"))
        _ = await other.next()
        let early = await harness.server.open("early", first: [.notice(Notice(level: .information, text: "start"))])
        #expect(await early.next()?.kind == .notice(Notice(level: .information, text: "start")))
        #expect(await early.next()?.kind == .agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "first")))
    }

    /// A resumed thread must not show again what came after its close.
    @Test func theLinesOfAClosedThreadDoNotWaitForItsResume() async throws {
        let harness = try await CodexServerHarness()
        let other = await harness.server.open("other", first: [])
        _ = await harness.server.open("a", first: [])
        await harness.server.closeThread("a")
        harness.serve(delta("a", "stale"))
        let request = await harness.nextWritten()
        #expect(request?["method"] == .string("thread/unsubscribe"))
        harness.serve(#"{"id":\#(request?["id"]?.integer ?? -1),"result":{}}"#)
        let deadline = ContinuousClock.now + .seconds(10)
        while await !harness.server.unsubscribingThreads.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        // Codex took the unsubscribe, so this line belongs to a resume.
        harness.serve(delta("a", "early"))
        harness.serve(delta("other", "mark"))
        _ = await other.next()
        let resumed = await harness.server.open("a", first: [])
        #expect(await resumed.next()?.kind == .agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "early")))
        #expect(await harness.server.earlyLines.isEmpty)
    }

    @Test func theEndOfTheServerEndsEveryThread() async throws {
        let harness = try await CodexServerHarness()
        let thread = await harness.server.open("a", first: [])
        harness.transport.close()
        #expect(await thread.next()?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: false)))
        #expect(await thread.next() == nil)
        #expect(await harness.server.hasEnded)
    }
}

@Suite struct CodexServerRequestTests {
    @Test func aRequestThatOpenRunDoesNotServeIsRefused() async throws {
        let harness = try await CodexServerHarness()
        let thread = await harness.server.open("a", first: [])
        harness.serve(#"{"id":5,"method":"item/tool/requestUserInput","params":{"threadId":"a","questions":[]}}"#)
        let refusal = await harness.nextWritten()
        #expect(refusal?["id"] == .number(5))
        #expect(refusal?["error"]?["code"] == .number(-32601))
        #expect(await thread.next()?.kind == .notice(Notice(
            level: .warning, text: "Codex asked for item/tool/requestUserInput, which OpenRun does not support, so OpenRun refused it.")))
    }
}
