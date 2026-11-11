import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct UserMessageRowViewTests {
    @Test func aShortMessageHasANarrowBubbleAtTheRight() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.transcript = Transcript(events: [TestEvents.user("1", "Thanks.")])
        let view = UserMessageRowView(frame: .zero)
        view.configure(TranscriptRow(key: "user:1", kind: .userMessage(item: "user:1")), context: context)
        view.frame.size = NSSize(width: 600, height: view.height(forWidth: 600))
        view.layout()
        #expect(view.bubble.frame.width < 120)
        #expect(view.bubble.frame.maxX == ChatColumn.frame(inWidth: 600).x + ChatColumn.frame(inWidth: 600).width)
    }
}
