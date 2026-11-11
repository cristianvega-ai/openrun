import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct ChatViewControllerTests {
    let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "thread", title: "A thread", agentName: "Claude Code"))

    @Test func aTranscriptShowsAsRows() {
        controller.show(Transcript(events: [TestEvents.user("1", "Hello"), TestEvents.text("a", "Hi."), TestEvents.turnEnd()]))
        #expect(controller.transcriptView.rows.map(\.key) == ["user:1", "text:a#0"])
    }

    @Test func anUpdateShowsTheNewText() {
        controller.view.frame.size = NSSize(width: 600, height: 400)
        var transcript = Transcript(events: [TestEvents.user("1", "Hello"), TestEvents.delta("a", "One")])
        controller.show(transcript)
        controller.view.layoutSubtreeIfNeeded()
        let change = transcript.apply(TestEvents.delta("a", " two"))
        controller.update(transcript, change: change)
        #expect(controller.context.text(ofBlocks: 0..<1, in: "text:a").string == "One two")
        #expect(controller.transcriptView.rowViews.views.keys.sorted() == ["activity", "text:a#0", "user:1"])
    }
}
