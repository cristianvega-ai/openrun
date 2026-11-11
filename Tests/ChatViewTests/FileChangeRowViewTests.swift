import AgentConversation
import Testing

@testable import ChatView

@MainActor struct FileChangeRowViewTests {
    @Test func aChangeShowsItsCountsAndOpensToTheDiff() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.transcript = Transcript(events: [TestEvents.fileChange("e1", "/work/a/Sources/Chat/Row.swift", "@@ -1 +1,2 @@\n-a\n+b\n+c")])
        let row = TranscriptRow(key: "file:e1", kind: .fileChange(item: "file:e1"))
        let view = FileChangeRowView()
        view.configure(row, context: context)
        #expect(view.line.title.stringValue == "…/Sources/Chat/Row.swift")
        #expect(view.line.status.stringValue == "+2 \u{2212}1")
        #expect(view.parts.count == 1)
        context.openedParts = [row.key]
        view.configure(row, context: context)
        #expect(view.parts.count == 2)
        #expect(view.height(forWidth: 600) > DisclosureLineView.height + 4 * 15)
    }
}
