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
