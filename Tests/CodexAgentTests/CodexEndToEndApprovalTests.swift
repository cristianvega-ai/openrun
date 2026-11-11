import AgentConversation
import Testing
@testable import CodexAgent

/// Approvals between the fake app-server and the user, through a
/// transcript. The fake ends with the status 0 only when each answer was
/// the expected one.
@Suite struct CodexEndToEndApprovalTests {
    /// Runs turns that each wait for one approval and gives the answers in
    /// order. A nil answer gives none. Returns the events of every turn.
    func run(_ fixtures: [String], answers: [CodexPermissionAnswer?], options: CodexServerOptions = CodexServerOptions())
        async throws -> [ConversationEvent] {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start"] + fixtures), options: options)
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        var events: [ConversationEvent] = []
        for answer in answers {
            try await thread.startTurn(CodexTurn(messageIdentifier: "message-\(events.count)", text: "Run the command."))
            for await event in thread.events {
                events.append(event)
                if case .permissionRequested(let request) = event.kind, let answer {
                    await thread.answerPermission(identifier: request.identifier, answer: answer)
                }
                if case .turnEnded = event.kind { break }
            }
        }
        await server.shutDown()
        events += await CodexFakeServer.events(of: thread)
        return events
    }

    @Test func anAcceptedAndADeclinedCommand() async throws {
        let events = try await run(["command-accepted", "command-declined"], answers: [.allow, .deny])
        let calls = Transcript(events: events).items.compactMap { if case .toolCall(let call) = $0.content { call } else { nil } }
        #expect(calls.map(\.state) == [.succeeded, .refused])
        #expect(events.last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }

    @Test func aRequestWithoutAnswerIsDeclinedAtTheTimeLimit() async throws {
        let options = CodexServerOptions(approvalTimeLimit: .milliseconds(200))
        let events = try await run(["command-accepted", "command-declined"], answers: [.allow, nil], options: options)
        #expect(events.contains { if case .permissionEnded(let end) = $0.kind { end.outcome == .timedOut } else { false } })
        #expect(events.last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }

    @Test func aConnectionThatClosesWhileARequestWaitsDeclinesItAndRunsNothing() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start", "closed-during-approval"]))
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Run the command."))
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if case .permissionRequested = event.kind { await server.shutDown() }
        }
        #expect(events.contains { if case .permissionEnded(let end) = $0.kind { end.outcome == .cancelled } else { false } })
        // The fake app-server ends with the status 3 when any line comes
        // while the request waits.
        #expect(events.last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }
}
