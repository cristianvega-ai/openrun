import Testing
import AgentConversation

@Suite struct TranscriptTests {
    @Test func noticesAndUnknownLinesBecomeRowsAndFactsStayAside() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.agentStarted(AgentStart(model: "claude-haiku-5-5"))))
        let change = transcript.apply(ConversationEvent(.notice(Notice(level: .warning, text: "Retry"))))
        transcript.apply(ConversationEvent(.unknown(UnknownLine(reason: .notJSON, text: "oops", byteCount: 4))))
        transcript.apply(ConversationEvent(.usage(UsageReading(windows: [], status: "allowed"))))
        #expect(change.inserted == ["notice:2"])
        #expect(transcript.items.map(\.identifier) == ["notice:2", "unknown:3"])
        #expect(transcript.agentStart?.model == "claude-haiku-5-5")
        #expect(transcript.usage?.status == "allowed")
    }

    @Test func theOldestRowsGoAtTheLimitAndTheTranscriptCountsThem() {
        var transcript = Transcript(limits: TranscriptLimits(itemLimit: 2))
        var removed: [String] = []
        for _ in 0..<5 {
            removed += transcript.apply(ConversationEvent(.notice(Notice(level: .information, text: "n")))).removed
        }
        #expect(removed == ["notice:1", "notice:2", "notice:3"])
        #expect(transcript.items.map(\.identifier) == ["notice:4", "notice:5"])
        #expect(transcript.removedItemCount == 3)
    }
}

@Suite struct TranscriptMessageTests {
    @Test func theAgentsCopyOfAMessageMarksTheSentMessageAsTaken() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.userMessage(UserMessage(identifier: "u1", text: "Hi", isAccepted: false))))
        let change = transcript.apply(ConversationEvent(.userMessage(UserMessage(identifier: "u1", text: "Hi", isAccepted: true))))
        #expect(change.updated == ["user:u1"])
        #expect(transcript.items == [TranscriptItem(
            identifier: "user:u1", content: .userMessage(UserMessage(identifier: "u1", text: "Hi", isAccepted: true)))])
    }

    @Test func piecesOfTextGrowOneItemAndTheCompleteTextReplacesThem() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.thinking(Thinking(itemIdentifier: "m:0", estimatedTokens: 50, isComplete: false))))
        transcript.apply(ConversationEvent(.thinking(Thinking(estimatedTokens: 300, isComplete: false))))
        #expect(transcript.thinking == Thinking(itemIdentifier: "m:0", estimatedTokens: 300, isComplete: false))
        #expect(transcript.apply(ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: "m:1", text: "Hel")))).inserted == ["text:m:1"])
        #expect(transcript.apply(ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: "m:1", text: "lo")))).updated == ["text:m:1"])
        #expect(transcript.items.first?.content == .agentMessage(AgentMessage(text: "Hello", isComplete: false)))
        transcript.apply(ConversationEvent(.agentText(AgentText(itemIdentifier: "m:1", text: "Hello."))))
        #expect(transcript.items.first?.content == .agentMessage(AgentMessage(text: "Hello.", isComplete: true)))
        #expect(transcript.thinking == nil)
    }

    @Test func textThatStreamsWithoutEndStaysWithinItsLimit() {
        var transcript = Transcript(limits: TranscriptLimits(messageByteLimit: 10))
        for _ in 0..<100 {
            transcript.apply(ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "ab"))))
        }
        #expect(transcript.items.first?.content == .agentMessage(AgentMessage(text: "ababababab", isComplete: false)))
    }
}
