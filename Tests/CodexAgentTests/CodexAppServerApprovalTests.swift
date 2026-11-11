import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerApprovalTests {
    /// Starts a thread, plays a turn with one approval, gives the answer,
    /// and returns the events of the turn.
    func turn(_ name: String, answer: CodexPermissionAnswer?, options: CodexServerOptions = CodexServerOptions()) async throws
        -> [ConversationEvent] {
        let harness = try await CodexServerHarness(options: options)
        async let started = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        _ = try await started
        async let played = harness.play(name)
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Run the command."))
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if case .permissionRequested(let request) = event.kind, let answer {
                #expect(await thread.answerPermission(identifier: request.identifier, answer: answer))
                #expect(await !thread.answerPermission(identifier: request.identifier, answer: .allow))
            }
            if case .turnEnded = event.kind { break }
        }
        _ = try await played
        return events
    }

    @Test func anAllowedCommandRuns() async throws {
        let events = try await turn("command-accepted", answer: .allow)
        let identifier = "exec-00000000-0000-7000-8000-000000000003/0"
        #expect(events.contains { $0.kind == .permissionEnded(PermissionEnd(identifier: identifier, outcome: .allowed)) })
        let transcript = Transcript(events: events)
        #expect(transcript.items.contains { if case .toolCall(let call) = $0.content { call.state == .succeeded && call.exitCode == 0 } else { false } })
    }

    @Test func aDeniedCommandIsRefusedByTheUser() async throws {
        let events = try await turn("command-declined", answer: .deny)
        let identifier = "exec-00000000-0000-7000-8000-000000000007/1"
        #expect(events.contains { $0.kind == .permissionEnded(PermissionEnd(identifier: identifier, outcome: .denied)) })
        #expect(events.contains { if case .toolCallRefused(let refusal) = $0.kind { refusal.reason == .user } else { false } })
    }

    @Test func aRequestWithoutAnswerIsDeclinedAfterTheTimeLimit() async throws {
        let events = try await turn("command-declined", answer: nil, options: CodexServerOptions(approvalTimeLimit: .milliseconds(100)))
        let identifier = "exec-00000000-0000-7000-8000-000000000007/1"
        #expect(events.contains { if case .permissionEnded(let end) = $0.kind { end.identifier == identifier && end.outcome == .timedOut } else { false } })
        #expect(events.contains { if case .toolCallRefused(let refusal) = $0.kind { refusal.reason == .unanswered } else { false } })
    }
}
