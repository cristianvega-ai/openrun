import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerHistoryTests {
    @Test func twoPagesGiveTheTurnsOldestFirstWithTheirStops() async throws {
        let harness = try await CodexServerHarness()
        let channel = await harness.server.open("00000000-0000-7000-8000-000000000001", first: [])
        let thread = CodexThread(identifier: "00000000-0000-7000-8000-000000000001", events: channel.stream, server: harness.server, closed: nil)
        async let played = harness.play("history")
        let newest = try await thread.historyPage(turnLimit: 3)
        let older = try await thread.historyPage(cursor: newest.olderCursor, turnLimit: 3)
        let lines = try await played
        #expect(lines[1]["params"]?["cursor"] == newest.olderCursor.map(JSONValue.string))
        #expect(newest.olderCursor != nil)
        let stops = newest.events.filter { $0.kind == .notice(Notice(level: .information, text: CodexHistory.stoppedTurnText)) }
        #expect(stops.count == 2)
        let transcript = Transcript(events: older.events + newest.events)
        let ends = transcript.items.compactMap { if case .turnEnd(let end) = $0.content { end.outcome } else { nil } }
        #expect(ends == [.done, .stopped, .done, .stopped, .done, .stopped])
        let first = transcript.items.first { if case .userMessage = $0.content { true } else { false } }
        #expect(first?.content == .userMessage(UserMessage(
            identifier: "00000000-0000-7000-8000-000000000009",
            text: "Create the file notes.txt that holds the word hi. Use your file editing tool, not the shell.", isAccepted: true)))
    }
}
