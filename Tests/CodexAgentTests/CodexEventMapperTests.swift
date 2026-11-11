import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexEventMapperTests {
    @Test func aPlainTurnGivesItsMessagesUsageAndEnd() throws {
        let events = try CodexFixture(name: "plain-turn").events
        #expect(events.count == 11)
        #expect(events.contains(.turnStarted(TurnStart())))
        #expect(events.contains(.userMessage(UserMessage(
            identifier: "00000000-0000-7000-8000-000000000012", text: "Reply with the single word ok.", isAccepted: true))))
        #expect(events.contains(.agentTextDelta(AgentTextDelta(itemIdentifier: "msg_01Fixture00000004", text: "ok"))))
        #expect(events.contains(.agentText(AgentText(itemIdentifier: "msg_01Fixture00000004", text: "ok"))))
        let usage = TokenUsage(inputTokens: 483_378 - 420_096, outputTokens: 1_170, cacheReadInputTokens: 420_096)
        #expect(events.last == .turnEnded(TurnEnd(outcome: .done, usage: usage, durationMilliseconds: 4_167)))
        #expect(!events.contains { if case .unknown = $0 { true } else { false } })
    }

    @Test func aPlainTurnShowsInATranscript() throws {
        let transcript = Transcript(events: try CodexFixture(name: "plain-turn").events.map { ConversationEvent($0) })
        #expect(transcript.items.map(\.content) == [
            .userMessage(UserMessage(identifier: "00000000-0000-7000-8000-000000000012", text: "Reply with the single word ok.", isAccepted: true)),
            .agentMessage(AgentMessage(text: "ok", isComplete: true)),
            .turnEnd(TurnEnd(outcome: .done, usage: TokenUsage(inputTokens: 63_282, outputTokens: 1_170, cacheReadInputTokens: 420_096),
                             durationMilliseconds: 4_167)),
        ])
        #expect(transcript.state == .finishedTurn)
        #expect(transcript.usage?.windows.map(\.name) == ["seven_day"])
    }

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

    @Test func aFailedTurnGivesItsTextAndItsKind() {
        var mapper = CodexEventMapper()
        let error = JSONValue.object(["message": .string("The model is not supported."), "codexErrorInfo": .string("modelNotFound")])
        let end = mapper.events(method: "turn/completed", parameters: .object(["turn": .object(["status": .string("failed"), "error": error])]))
        #expect(end == [
            .turnEnded(TurnEnd(outcome: .failed, errorText: "The model is not supported.")),
            .agentStatus(AgentStatus(kind: "turn/error", detail: "modelNotFound")),
        ])
        let interrupted = mapper.events(method: "turn/completed", parameters: .object(["turn": .object(["status": .string("interrupted")])]))
        #expect(interrupted == [.turnEnded(TurnEnd(outcome: .stopped))])
        #expect(CodexEventMapper.errorKind(.object(["codexErrorInfo": .object(["httpConnectionFailed": .object([:])])])) == "httpConnectionFailed")
    }

    @Test func anEchoedUserMessageKeepsTheIdentifierOfTheClient() {
        var mapper = CodexEventMapper()
        mapper.pendingMessageIdentifiers = ["first", "second"]
        let item = JSONValue.object(["type": .string("userMessage"), "id": .string("item"),
                                     "content": .array([.object(["type": .string("text"), "text": .string("hi")])])])
        #expect(mapper.events(method: "item/started", parameters: .object(["item": item]))
            == [.userMessage(UserMessage(identifier: "first", text: "hi", isAccepted: true))])
        #expect(mapper.pendingMessageIdentifiers == ["second"])
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
