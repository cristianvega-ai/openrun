import AgentConversation
import Testing
@testable import ChatView

struct TranscriptRowBuilderTests {
    private func kinds(_ events: [ConversationEvent], earlier: Bool = false) -> [TranscriptRow.Kind] {
        var builder = TranscriptRowBuilder()
        return builder.rows(for: Transcript(events: events), changedItems: nil, showsEarlierItems: earlier).map(\.kind)
    }

    @Test func aMessageBecomesTextAndCodeRows() {
        let message = "Some text\n\n```swift\nlet a = 1\n```\n\nMore text\n\n- item"
        #expect(kinds([TestEvents.user("1", "Hi"), TestEvents.text("a", message), TestEvents.turnEnd()]) == [
            .userMessage(item: "user:1"), .agentText(item: "text:a", blocks: 0..<1), .agentCode(item: "text:a", block: 1),
            .agentText(item: "text:a", blocks: 2..<4),
        ])
    }

    @Test func aRunOfToolCallsIsOneRowAndCallsShownElsewhereLeaveIt() {
        let events = [
            TestEvents.tool("r1", "Read", ["file_path": "/a"]), TestEvents.tool("r2", "Read", ["file_path": "/b"]),
            TestEvents.tool("e1", "Edit", ["file_path": "/a"]), TestEvents.fileChange("e1", "/a", "@@"),
            TestEvents.tool("b1", "Bash", ["command": "ls"]),
        ]
        #expect(kinds(events) == [
            .toolCalls(items: ["tool:r1", "tool:r2"]), .fileChange(item: "file:e1"), .toolCalls(items: ["tool:b1"]), .activity,
        ])
    }

    @Test func aCallThatWaitsForTheUserShowsOnlyAsItsRequest() {
        let call = TestEvents.tool("b1", "Bash", ["command": "ls"])
        let request = TestEvents.permission("p1", "Bash", ["command": "ls"], call: "b1")
        #expect(kinds([call, request]) == [.permissionRequest(item: "permission:p1")])
        let allowed = [call, request, TestEvents.permissionEnd("p1", .allowed)]
        #expect(kinds(allowed) == [.toolCalls(items: ["tool:b1"]), .permissionRequest(item: "permission:p1"), .activity])
    }

    @Test func onlyTurnsThatDidNotEndWellHaveARow() {
        let events = [TestEvents.user("1", "Hi"), TestEvents.turnEnd(), TestEvents.user("2", "Again"), TestEvents.turnEnd(.stopped)]
        #expect(kinds(events, earlier: true) == [.earlierItems, .userMessage(item: "user:1"), .userMessage(item: "user:2"), .turnEnd(item: "turn:4")])
    }

    @Test func aLongMessageKeepsTheKeysOfItsFirstRowsAsItGrows() {
        var builder = TranscriptRowBuilder()
        var transcript = Transcript()
        var keys: [[String]] = []
        for index in 0..<60 {
            let change = transcript.apply(TestEvents.delta("a", "Paragraph \(index)\n\n"))
            keys.append(builder.rows(for: transcript, changedItems: Set(change.inserted + change.updated), showsEarlierItems: false).map(\.key))
        }
        #expect(keys.last?.filter { $0.hasPrefix("text:a#") }.count == 3)
        for (before, after) in zip(keys, keys.dropFirst()) {
            #expect(Array(after.prefix(before.count - 2)) == Array(before.prefix(before.count - 2)))
        }
    }
}
