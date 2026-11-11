import AgentConversation
import Testing

@testable import ChatView

@MainActor struct ActivityRowViewTests {
    @Test func theRowSaysWhetherTheAgentThinks() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.agentName = "Claude Code"
        context.transcript = Transcript(events: [TestEvents.user("1", "Hi")])
        let view = ActivityRowView()
        view.configure(TranscriptRow(key: "activity", kind: .activity), context: context)
        #expect(view.label.stringValue == "Working")
        #expect(view.accessibilityLabel() == "Claude Code is working")
        context.transcript.apply(ConversationEvent(.thinking(Thinking(isComplete: false))))
        view.configure(TranscriptRow(key: "activity", kind: .activity), context: context)
        #expect(view.label.stringValue == "Thinking")
    }
}
