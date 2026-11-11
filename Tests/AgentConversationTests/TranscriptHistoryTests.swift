import AgentConversation
import Testing

/// The earlier turns that a transcript takes from the history of the agent.
@Suite struct TranscriptHistoryTests {
    private func user(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.userMessage(UserMessage(identifier: identifier, text: text, isAccepted: true)))
    }

    private func text(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.agentText(AgentText(itemIdentifier: identifier, text: text)))
    }

    private let done = ConversationEvent(.turnEnded(TurnEnd(outcome: .done)))

    /// Two turns of the history, and a live transcript with the second one and a third one.
    private var history: [ConversationEvent] { [user("u1", "One"), text("m1:0", "First"), done, user("u2", "Two"), text("m2:0", "Second"), done] }
    private var live: Transcript { Transcript(events: [user("u2", "Two"), text("m2:0", "Second"), done, user("u3", "Three"), text("m3:0", "Thi")]) }

    @Test func earlierTurnsComeBeforeTheItemsAndAKnownTurnIsLeftOut() {
        var transcript = live
        let stayed = transcript.prepend(history: history, label: "page1")
        #expect(stayed == 3)
        #expect(transcript.items.map(\.identifier) == ["user:u1", "text:m1:0", "page1-0:turn:3", "user:u2", "text:m2:0", "turn:3", "user:u3", "text:m3:0"])
        // The thread goes on as before: its state stays, and a live event finds its item.
        #expect(transcript.state == .inProgress)
        transcript.apply(text("m3:0", "Third"))
        #expect(transcript.item(withIdentifier: "text:m3:0")?.content == .agentMessage(AgentMessage(text: "Third", isComplete: true)))
        #expect(transcript.item(withIdentifier: "user:u1")?.content == .userMessage(UserMessage(identifier: "u1", text: "One", isAccepted: true)))
        // The same page a second time brings nothing.
        #expect(transcript.prepend(history: history, label: "page2") == 0 && transcript.items.count == 8)
    }

    @Test func aTurnThatTheHistoryCutShortShowsNoWorkInProgress() {
        var transcript = Transcript()
        let call = ConversationEvent(.toolCallInput(ToolCallInput(identifier: "t1", name: "Bash", input: .object([:]))))
        #expect(transcript.prepend(history: [user("u1", "One"), call, text("m1:0", "Par")], label: "p") == 3)
        guard case .toolCall(let item) = transcript.item(withIdentifier: "tool:t1")?.content else { Issue.record("no tool call"); return }
        #expect(item.state == .interrupted && transcript.state == .idle)
        #expect(transcript.item(withIdentifier: "text:m1:0")?.content == .agentMessage(AgentMessage(text: "Par", isComplete: true)))
    }

    @Test func theOldestItemsGoWhenTheLimitsHaveNoRoom() {
        var transcript = Transcript(events: [user("u9", "Nine"), text("m9:0", "Ninth")], limits: TranscriptLimits(itemLimit: 4))
        let stayed = transcript.prepend(history: history, label: "p")
        #expect(stayed == 2 && transcript.removedItemCount == 4)
        #expect(transcript.items.map(\.identifier) == ["text:m2:0", "p-1:turn:3", "user:u9", "text:m9:0"])
        #expect(transcript.item(withIdentifier: "user:u1") == nil && transcript.item(withIdentifier: "user:u9") != nil)
    }
}
