import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerApprovalTests {
    /// Starts a thread, plays a turn with one approval, gives the answer,
    /// and returns the events of the turn.
    func turn(_ name: String, answer: CodexPermissionAnswer?, options: CodexServerOptions = CodexServerOptions(), sandbox: CodexSandbox? = nil) async throws
        -> [ConversationEvent] {
        let harness = try await CodexServerHarness(options: options)
        async let started = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        _ = try await started
        async let played = harness.play(name)
        try await thread.startTurn(CodexTurn(messageIdentifier: "message-1", text: "Run the command.", sandbox: sandbox))
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if case .permissionRequested(let request) = event.kind, let answer {
                #expect(await thread.answerPermission(identifier: request.identifier, answer: answer))
                #expect(await !thread.answerPermission(identifier: request.identifier, answer: .allow))
            }
            if case .turnEnded = event.kind { break }
            if case .processEnded = event.kind { break }
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

    @Test func aRequestThatWaitsWhenTheServerEndsIsDeclinedWithoutAnswer() async throws {
        let events = try await turn("closed-during-approval", answer: nil)
        let identifier = "exec-00000000-0000-7000-8000-000000000003/0"
        #expect(events.suffix(2).map(\.kind) == [
            .permissionEnded(PermissionEnd(identifier: identifier, outcome: .cancelled, message: "The Codex app-server ended, so the request was declined.")),
            .processEnded(ProcessEnd(exitStatus: 0, wasRequested: false)),
        ])
        #expect(!Transcript(events: events).items.contains { if case .toolCall(let call) = $0.content { call.state == .succeeded } else { false } })
    }

    @Test func theCloseOfTheThreadDeclinesItsRequests() async throws {
        let harness = try await CodexServerHarness()
        let channel = await harness.server.open("a", first: [])
        harness.serve(#"{"id":3,"method":"item/commandExecution/requestApproval","params":{"threadId":"a","itemId":"c","command":"ls"}}"#)
        guard case .permissionRequested? = await channel.next()?.kind else { Issue.record("No request"); return }
        let close = Task { await harness.server.closeThread("a") }
        #expect(await harness.nextWritten() == .object(["id": .number(3), "result": .object(["decision": .string("decline")])]))
        #expect(await channel.next()?.kind == .permissionEnded(PermissionEnd(identifier: "c/3", outcome: .cancelled, message: "OpenRun declined the request.")))
        let unsubscribe = await harness.nextWritten()
        harness.serve(#"{"id":\#(unsubscribe?["id"]?.integer ?? 0),"result":{}}"#)
        await close.value
    }

    @Test func anAllowedFileChangeShowsItsDiffFirst() async throws {
        let events = try await turn("file-change", answer: .allow, sandbox: .readOnly)
        let request = events.compactMap { if case .permissionRequested(let request) = $0.kind { request } else { nil } }.first
        #expect(request?.input["changes"]?.array?.first?["diff"] == .string("@@ -0,0 +1,1 @@\n+hi"))
        #expect(events.contains { if case .permissionEnded(let end) = $0.kind { end.outcome == .allowed } else { false } })
    }

    @Test func aRequestBeforeTheStartOfItsItemShowsAgainWithTheDiff() async throws {
        let harness = try await CodexServerHarness()
        let channel = await harness.server.open("a", first: [])
        harness.serve(#"{"id":4,"method":"item/fileChange/requestApproval","params":{"threadId":"a","itemId":"f"}}"#)
        harness.serve(#"{"method":"item/started","params":{"threadId":"a","item":{"type":"fileChange","id":"f","changes":[{"path":"/work/project/a","kind":{"type":"add"},"diff":"x"}]}}}"#)
        var requests: [PermissionRequest] = []
        while requests.count < 2, let event = await channel.next() {
            if case .permissionRequested(let request) = event.kind { requests.append(request) }
        }
        #expect(requests.map(\.identifier) == ["f/4", "f/4"])
        #expect(requests.last?.input["changes"]?.array?.count == 1)
        #expect(Transcript(events: requests.map { ConversationEvent(.permissionRequested($0)) }).items.count == 1)
    }
}
