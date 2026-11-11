import AppKit
import MarkdownText
import Testing

@testable import ChatView

@MainActor struct AgentTextRowViewTests {
    final class Actions: TranscriptRowActions {
        var links: [String] = []
        func openLink(_ target: String) { links.append(target) }
        func toggle(_ part: String, in row: TranscriptRowView) {}
        func loadEarlierHistory() {}
        func answerPermissionRequest(_ identifier: String, with answer: ChatPermissionAnswer) {}
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

    @Test func copyMessageCopiesTheMarkdownOfTheWholeMessage() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.documents["text:a"] = MarkdownDocument(text: "# Title\n\nSome **bold** text.", isComplete: true)
        let view = AgentTextRowView()
        view.configure(TranscriptRow(key: "text:a#0", kind: .agentText(item: "text:a", blocks: 0..<1)), context: context)
        view.textView.pasteboard = NSPasteboard.withUniqueName()
        defer { view.textView.pasteboard.releaseGlobally() }
        let menu = view.textView.textView(view.textView, menu: NSMenu(), for: NSEvent(), at: 0)
        #expect(menu?.items.first?.title == "Copy Message")
        view.textView.copyMessage()
        #expect(view.textView.pasteboard.string(forType: .string) == "# Title\n\nSome **bold** text.")
    }
}
