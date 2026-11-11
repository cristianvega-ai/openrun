import AppKit
import MarkdownText
import Testing

@testable import ChatView

@MainActor struct CodeBlockRowViewTests {
    @Test func aCodeBlockShowsItsCodeWithoutWrapAndCopiesIt() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        let long = String(repeating: "word ", count: 60)
        context.documents["text:a"] = MarkdownDocument(text: "```swift\nlet a = 1\n\(long)\n```", isComplete: true)
        let view = CodeBlockRowView()
        view.configure(TranscriptRow(key: "text:a#0", kind: .agentCode(item: "text:a", block: 0)), context: context)
        #expect(view.language.stringValue == "swift")
        view.frame = NSRect(x: 0, y: 0, width: 400, height: view.height(forWidth: 400))
        view.layout()
        #expect(view.frame.height < 90)
        #expect(view.textView.frame.width > view.scrollView.frame.width)
        view.pasteboard = NSPasteboard.withUniqueName()
        view.copyCode()
        #expect(view.pasteboard.string(forType: .string) == "let a = 1\n" + long)
        view.pasteboard.releaseGlobally()
    }
}
