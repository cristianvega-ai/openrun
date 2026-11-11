import Testing
import AgentConversation

@Suite struct TranscriptRequestTests {
    let request = PermissionRequest(identifier: "p", toolName: "Bash", input: .object(["command": .string("touch a")]), toolCallIdentifier: "c")

    @Test func aWaitingRequestNeedsTheUserUntilItEnds() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.toolCallInput(ToolCallInput(identifier: "c", name: "Bash", input: request.input))))
        transcript.apply(ConversationEvent(.permissionRequested(request)))
        #expect(transcript.state == .needsUser)
        transcript.apply(ConversationEvent(.thinking(Thinking(isComplete: false))))
        #expect(transcript.state == .needsUser)
        transcript.apply(ConversationEvent(.permissionEnded(PermissionEnd(identifier: "p", outcome: .allowed))))
        #expect(transcript.state == .inProgress)
        #expect(transcript.item(withIdentifier: "permission:p")?.content == .permissionRequest(
            PermissionRequestItem(request: request, end: PermissionEnd(identifier: "p", outcome: .allowed))))
    }

    @Test func theEndOfATurnCancelsARequestThatStillWaits() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.permissionRequested(request)))
        transcript.apply(ConversationEvent(.turnEnded(TurnEnd(outcome: .stopped))))
        #expect(transcript.state == .idle)
        #expect(transcript.item(withIdentifier: "permission:p")?.content == .permissionRequest(
            PermissionRequestItem(request: request, end: PermissionEnd(identifier: "p", outcome: .cancelled))))
        // A late answer does not change an ended request.
        transcript.apply(ConversationEvent(.permissionEnded(PermissionEnd(identifier: "p", outcome: .allowed))))
        #expect(transcript.state == .idle)
    }

    @Test func aTaskGathersItsMessagesAlsoWhenOneComesFirst() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.taskMessage(TaskMessage(toolCallIdentifier: "c", text: "Reply ok."))))
        let start = TaskStart(identifier: "t", toolCallIdentifier: "c", description: "Check", agentType: "general-purpose", prompt: "Reply ok.")
        transcript.apply(ConversationEvent(.taskStarted(start)))
        for index in 0..<60 { transcript.apply(ConversationEvent(.taskMessage(TaskMessage(toolCallIdentifier: "c", text: "\(index)")))) }
        transcript.apply(ConversationEvent(.taskEnded(TaskEnd(identifier: "t", toolCallIdentifier: "c", status: "completed", summary: "ok"))))
        #expect(transcript.items.map(\.identifier) == ["task:c"])
        guard case .task(let task) = transcript.items.first?.content else { Issue.record("no task"); return }
        #expect(task.start == start)
        #expect(task.messages.count == 50)
        #expect(task.messages.last == "59")
        #expect(task.removedMessageCount == 11)
        #expect(task.end?.summary == "ok")
    }

    @Test func theSameEventsGiveTheSameTranscript() {
        let events = oneEventOfEachKind.map { ConversationEvent($0) }
        let first = Transcript(events: events)
        #expect(Transcript(events: events) == first)
        #expect(first.items.map(\.identifier) == [
            "user:u", "text:t", "tool:c1", "file:f", "task:s", "permission:p", "turn:19", "notice:21", "notice:23", "unknown:24",
        ])
    }
}
