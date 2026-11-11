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

    @Test func aLinkGoesToTheHost() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.openLink("https://example.com")
        #expect(delegate.requests == ["link https://example.com"])
    }

    @Test func aNewAppearanceKeepsTheRows() {
        controller.show(Transcript(events: [TestEvents.user("1", "Hello")]))
        controller.appearance = ChatAppearance(light: ChatAppearance.graphite.light, dark: ChatAppearance.graphite.dark, bodyFontSize: 16)
        #expect(controller.context.palette.bodyFont.pointSize == 16)
        #expect(controller.transcriptView.rows.count == 2)
    }

    @Test func anAnswerGoesToTheHost() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.answerPermissionRequest("p1", with: .deny(message: "Not now"))
        #expect(delegate.requests == ["answer p1 deny(message: Optional(\"Not now\"))"])
    }
}
