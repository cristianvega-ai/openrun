import AgentConversation
import Testing

@testable import ChatView

@MainActor struct ToolCallsRowViewTests {
    @Test func aLongRunShowsOneLineUntilItOpens() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.transcript = Transcript(events: (1...4).map { TestEvents.tool("\($0)", "Read", ["file_path": "/f\($0).swift"]) })
        let row = TranscriptRow(key: "group:tool:1", kind: .toolCalls(items: (1...4).map { "tool:\($0)" }))
        let view = ToolCallsRowView()
        view.configure(row, context: context)
        #expect(view.height(forWidth: 600) == DisclosureLineView.height)
        context.openedParts = [row.key, "tool:2"]
        view.configure(row, context: context)
        let lines = view.subviews.compactMap { $0 as? DisclosureLineView }
        #expect(lines.map(\.title.stringValue) == ["Read 4 files"] + (1...4).map { "Read f\($0).swift" })
        #expect(view.subviews.contains { $0 is DetailBoxView })
        #expect(view.height(forWidth: 600) > 5 * DisclosureLineView.height)
    }
}
