import AgentConversation
import Testing
@testable import CodexAgent

/// The servers of the accounts, the usage and the history against the
/// fake app-server.
@Suite struct CodexEndToEndAccountTests {
    @Test func twoThreadsShareOneServerThatEndsAfterTheLastClose() async throws {
        let servers = CodexAccountServers(launch: CodexFakeServer.launch(["thread-start", "second-thread"]))
        let first = try await servers.startThread(account: "/config/codex", CodexThreadStart(folder: "/work/project"))
        let second = try await servers.startThread(account: "/config/codex", CodexThreadStart(folder: "/work/second"))
        #expect(first.server === second.server)
        #expect(second.identifier == "00000000-0000-7000-8000-000000000031")
        #expect(await servers.serverCount == 1)
        await first.close()
        #expect(await servers.serverCount == 1)
        #expect(await !second.server.hasEnded)
        await second.close()
        #expect(await servers.serverCount == 0)
        while await !second.server.hasEnded { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func theUsageAndTheHistoryComeWithoutATurn() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["usage", "thread-start", "history"]))
        #expect(try await server.readAccount().plan == "plus")
        #expect(try await server.readUsage().windows.map(\.lengthInMinutes) == [10_080])
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        let newest = try await thread.historyPage(turnLimit: 3)
        let older = try await thread.historyPage(cursor: newest.olderCursor, turnLimit: 3)
        let ends = Transcript(events: older.events + newest.events).items.filter { if case .turnEnd = $0.content { true } else { false } }
        #expect(ends.count == 6)
        await server.shutDown()
        var events: [ConversationEvent] = []
        for await event in thread.events { events.append(event) }
        #expect(events.last?.kind == .processEnded(ProcessEnd(exitStatus: 0, wasRequested: true, standardErrorText: "")))
    }
}
