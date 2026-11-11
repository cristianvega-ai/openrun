import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerThreadTests {
    let main = "00000000-0000-7000-8000-000000000001"

    @Test func aNewThreadGivesItsStartAndItsNotifications() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("thread-start")
        let thread = try await harness.server.startThread(CodexThreadStart(folder: "/work/project"))
        try await played
        #expect(thread.identifier == main)
        var events = thread.events.makeAsyncIterator()
        #expect(await events.next()?.kind == .agentStarted(AgentStart(
            conversationIdentifier: main, model: "gpt-example", permissionMode: "untrusted", agentVersion: "0.100.0",
            workingFolder: "/work/project")))
        #expect(await events.next()?.kind == .agentStatus(AgentStatus(kind: "thread/started", detail: "idle")))
        #expect(await events.next()?.kind == .agentStatus(AgentStatus(kind: "mcpServer/startupStatus/updated", detail: "starting")))
        #expect(await harness.server.openThreadCount == 1)
    }
}
