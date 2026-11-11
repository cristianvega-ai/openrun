import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexEventMapperTests {
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
