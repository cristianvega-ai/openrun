import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerThreadTests {
    let main = "00000000-0000-7000-8000-000000000001"

    @Test func aNewThreadGivesItsStartAndItsNotifications() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        _ = try await played
        #expect(thread.identifier == main)
        var events = thread.events.makeAsyncIterator()
        #expect(await events.next()?.kind == .agentStarted(AgentStart(
            conversationIdentifier: main, model: "gpt-example", permissionMode: "untrusted", agentVersion: "0.100.0",
            workingFolder: "/work/project")))
        #expect(await events.next()?.kind == .agentStatus(AgentStatus(kind: "thread/started", detail: "idle")))
        #expect(await events.next()?.kind == .agentStatus(AgentStatus(kind: "mcpServer/startupStatus/updated", detail: "starting")))
        #expect(await harness.server.openThreadCount == 1)
    }

    @Test func aClosedThreadEndsItsEventsAndLeavesTheServer() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        _ = try await played
        let close = Task { await thread.close() }
        let unsubscribe = await harness.nextWritten()
        #expect(unsubscribe?["method"] == .string("thread/unsubscribe"))
        harness.serve(#"{"id":\#(unsubscribe?["id"]?.integer ?? 0),"result":{}}"#)
        await close.value
        var count = 0
        for await _ in thread.events { count += 1 }
        #expect(count <= 3)
        #expect(await harness.server.openThreadCount == 0)
    }

    @Test func anUnknownThreadIsRefused() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("unknown-thread")
        await #expect(throws: CodexRequestError.self) {
            try await harness.server.resumeThread(identifier: "00000000-0000-7000-8000-000000000019", CodexThreadStart(folder: "/work/project"))
        }
        _ = try await played
    }

    @Test func aResumedThreadGetsTheStatusThatCameBeforeItsAnswer() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("resume")
        let resumed = "00000000-0000-7000-8000-000000000013"
        let thread = try await harness.server.resumeThread(identifier: resumed, CodexThreadStart(folder: "/work/project"))
        _ = try await played
        var events = thread.events.makeAsyncIterator()
        guard case .agentStarted(let start)? = await events.next()?.kind else { Issue.record("No start"); return }
        #expect(start.conversationIdentifier == resumed)
        #expect(await events.next()?.kind == .agentStatus(AgentStatus(kind: "thread/status/changed", detail: "idle")))
    }
}
