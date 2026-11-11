import Testing
@testable import AgentConversation

/// What the transcript keeps about items that it dropped stays bounded.
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
    }
}
