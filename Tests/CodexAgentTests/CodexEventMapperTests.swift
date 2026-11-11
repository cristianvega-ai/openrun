import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexEventMapperTests {
    @Test func theNextTurnCountsOnlyItsOwnTokens() {
        var mapper = CodexEventMapper()
        func total(_ input: Double, _ output: Double) -> JSONValue {
            .object(["tokenUsage": .object(["total": .object(["inputTokens": .number(input), "cachedInputTokens": .number(0),
                                                               "outputTokens": .number(output)])])])
        }
        _ = mapper.events(method: "thread/tokenUsage/updated", parameters: total(100, 10))
        _ = mapper.events(method: "turn/started", parameters: .object(["turn": .object(["id": .string("t")])]))
        _ = mapper.events(method: "thread/tokenUsage/updated", parameters: total(150, 25))
        let end = mapper.events(method: "turn/completed", parameters: .object(["turn": .object(["id": .string("t"), "status": .string("completed")])]))
        #expect(end == [.turnEnded(TurnEnd(outcome: .done, usage: TokenUsage(inputTokens: 50, outputTokens: 15)))])
        #expect(mapper.activeTurn == nil)
    }

    @Test func warningsAndErrorsAreNotices() {
        var mapper = CodexEventMapper()
        let retry = mapper.events(method: "error", parameters: .object(["error": .object(["message": .string("busy")]), "willRetry": .bool(true)]))
        #expect(retry == [.notice(Notice(level: .warning, text: "Codex tries the request again: busy"))])
        #expect(mapper.events(method: "warning", parameters: .object(["message": .string("w")])) == [.notice(Notice(level: .warning, text: "w"))])
        #expect(mapper.events(method: "no/such/method", parameters: .null) == nil)
    }

    @Test func aStatusKeepsTheStateOfTheThread() {
        var mapper = CodexEventMapper()
        let status = JSONValue.object(["status": .object(["type": .string("active"), "activeFlags": .array([.string("waitingOnApproval")])])])
        #expect(mapper.events(method: "thread/status/changed", parameters: status)
            == [.agentStatus(AgentStatus(kind: "thread/status/changed", detail: "active waitingOnApproval"))])
    }
}
