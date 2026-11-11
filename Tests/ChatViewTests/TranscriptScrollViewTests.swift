import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct TranscriptScrollViewTests {
    let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
    let scrollView: TranscriptScrollView

    init() {
        scrollView = TranscriptScrollView(transcriptView: TranscriptView(context: context))
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        show(messages: 60)
    }

    func show(messages count: Int) {
        context.transcript = Transcript(events: (0..<count).map { TestEvents.user("\($0)", "Message \($0)") })
        let rows = (0..<count).map { TranscriptRow(key: "user:\($0)", kind: .userMessage(item: "user:\($0)")) }
        scrollView.transcriptView.setRows(rows, changed: [])
    }

    @Test func theViewFollowsTheNewestRow() {
        #expect(scrollView.distanceFromBottom == 0)
        show(messages: 61)
        #expect(scrollView.distanceFromBottom == 0)
        #expect(scrollView.transcriptView.rowViews.views["user:60"] != nil)
    }

    @Test func aNewSizeIsNoScrollOfTheUser() {
        scrollView.frame.size = NSSize(width: 360, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.transcriptView.isFollowingBottom)
        #expect(scrollView.distanceFromBottom == 0)
    }
}
