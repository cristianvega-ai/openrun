import AppKit
import MarkdownText
import Testing

@testable import ChatView

@MainActor struct AgentTextRowViewTests {
    final class Actions: TranscriptRowActions {
        var links: [String] = []
        func openLink(_ target: String) { links.append(target) }
        func toggle(_ part: String, in row: TranscriptRowView) {}
    }

    @Test func aRowShowsItsBlocksAndSendsLinksToTheActions() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        let actions = Actions()
        context.actions = actions
        context.documents["text:a"] = MarkdownDocument(text: "Read [the notes](https://example.com).", isComplete: true)
        let view = AgentTextRowView()
        view.configure(TranscriptRow(key: "text:a#0", kind: .agentText(item: "text:a", blocks: 0..<1)), context: context)
        #expect(view.textView.string == "Read the notes.")
        #expect(view.height(forWidth: 600) > 10)
        _ = view.textView.textView(view.textView, clickedOnLink: "https://example.com", at: 5)
        #expect(actions.links == ["https://example.com"])
    }
}
