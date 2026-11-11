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
}
