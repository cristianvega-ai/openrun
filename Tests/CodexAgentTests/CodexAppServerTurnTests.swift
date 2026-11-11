import AgentConversation
import Foundation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerTurnTests {
    @Test func theMessageShowsAtOnceAndCodexTakesIt() async throws {
        let harness = try await CodexServerHarness()
        async let started = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        _ = try await started
        async let played = harness.play("plain-turn")
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Reply with the single word ok."))
        _ = try await played
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if case .turnEnded = event.kind { break }
        }
        let messages = Transcript(events: events).items.compactMap { item -> UserMessage? in
            if case .userMessage(let message) = item.content { message } else { nil }
        }
        #expect(messages == [UserMessage(identifier: "message-1", text: "Reply with the single word ok.", isAccepted: true)])
        #expect(events.contains { $0.kind == .agentText(AgentText(itemIdentifier: "msg_01Fixture00000004", text: "ok")) })
    }
}
