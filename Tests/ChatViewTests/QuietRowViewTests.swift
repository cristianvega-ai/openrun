import AgentConversation
import Testing

@testable import ChatView

@MainActor struct QuietRowViewTests {
    @Test func aLineWithDetailsOpensAndALineWithoutDoesNot() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.transcript = Transcript(events: [TestEvents.notice("Retry\nsoon", level: .warning), TestEvents.notice("Compacted")])
        let identifiers = context.transcript.items.map(\.identifier)
        let open = QuietRowView()
        context.openedParts = Set(identifiers)
        open.configure(TranscriptRow(key: identifiers[0], kind: .notice(item: identifiers[0])), context: context)
        #expect(open.parts.count == 2)
        let closed = QuietRowView()
        closed.configure(TranscriptRow(key: identifiers[1], kind: .notice(item: identifiers[1])), context: context)
        #expect(closed.parts.count == 1)
        #expect(!closed.line.acceptsFirstResponder)
        #expect(closed.accessibilityLabel() == "Notice")
    }
}
