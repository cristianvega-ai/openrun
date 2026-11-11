import Testing
@testable import AgentConversation

/// What the transcript keeps about items that it dropped stays bounded,
/// and a late event of a dropped item does not bring a part of it back.
@Suite struct TranscriptTrimTests {
    static func event(_ kind: ConversationEventKind) -> ConversationEvent { ConversationEvent(kind) }

    @Test func theMapsShrinkWithTheItems() {
        var transcript = Transcript(limits: TranscriptLimits(itemLimit: 100))
        for index in 0..<20_000 {
            transcript.apply(Self.event(.taskMessage(TaskMessage(toolCallIdentifier: "call\(index)", text: "x"))))
            transcript.apply(Self.event(.toolCallStarted(ToolCallStart(identifier: "tool\(index)", name: "Bash"))))
            transcript.apply(Self.event(.permissionRequested(PermissionRequest(identifier: "ask\(index)", toolName: "Bash", input: .null))))
        }
        #expect(transcript.items.count == 100)
        #expect(transcript.taskItems.count <= 100)
        #expect(transcript.openItems.count <= 100)
        #expect(transcript.waitingPermissions.count <= 100)
        #expect(transcript.droppedItems.count <= 1_024)
    }

    @Test func aLateEventOfADroppedItemChangesNothing() {
        var transcript = Transcript(limits: TranscriptLimits(itemLimit: 2))
        transcript.apply(Self.event(.agentTextDelta(AgentTextDelta(itemIdentifier: "m:0", text: "early"))))
        transcript.apply(Self.event(.toolCallStarted(ToolCallStart(identifier: "t1", name: "Bash"))))
        transcript.apply(Self.event(.taskMessage(TaskMessage(toolCallIdentifier: "c1", text: "early"))))
        for index in 0..<3 { transcript.apply(Self.event(.notice(Notice(level: .information, text: "\(index)")))) }
        let before = transcript.items
        #expect(transcript.apply(Self.event(.agentTextDelta(AgentTextDelta(itemIdentifier: "m:0", text: "late")))).isEmpty)
        #expect(transcript.apply(Self.event(.toolCallResult(ToolCallResult(identifier: "t1", output: "late", isError: false)))).isEmpty)
        #expect(transcript.apply(Self.event(.taskMessage(TaskMessage(toolCallIdentifier: "c1", text: "late")))).isEmpty)
        #expect(transcript.items == before)
        // A result whose call was never seen still makes the call.
        transcript.apply(Self.event(.toolCallResult(ToolCallResult(identifier: "t2", output: "new", isError: false))))
        #expect(transcript.item(withIdentifier: "tool:t2") != nil)
    }
}
