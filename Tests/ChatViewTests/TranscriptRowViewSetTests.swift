import AppKit
import MarkdownText
import Testing

@testable import ChatView

@MainActor struct TranscriptRowViewSetTests {
    let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
    let container = NSView()
    let row = TranscriptRow(key: "text:a#0", kind: .agentText(item: "text:a", blocks: 0..<1))

    @Test func aRowKeepsItsViewAndShowsAChange() {
        var set = TranscriptRowViewSet()
        context.documents["text:a"] = MarkdownDocument(text: "One", isComplete: false)
        let view = set.view(for: row, context: context, in: container)
        context.documents["text:a"]?.update(text: "One two", isComplete: false)
        set.markChanged([row.key])
        #expect(set.view(for: row, context: context, in: container) === view)
        #expect((view as? AgentTextRowView)?.textView.string == "One two")
        #expect(view.superview === container)
    }

    @Test func aRemovedViewLeavesTheContainer() {
        var set = TranscriptRowViewSet()
        let view = set.view(for: row, context: context, in: container)
        set.removeViews { _ in false }
        #expect(set.views.isEmpty)
        #expect(view.superview == nil)
    }
}
