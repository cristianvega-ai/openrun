import AppKit
import Testing

@testable import ChatView

@MainActor struct DetailBoxViewTests {
    @Test func theBoxShowsEachPartAndItsNote() {
        let box = DetailBoxView()
        box.show([("swift test", nil), ("line 1\nline 2", "3 more lines")], palette: ChatPalette(appearance: .graphite))
        #expect(box.textView.string == "swift test\nline 1\nline 2\n3 more lines")
        #expect(box.height(forWidth: 400) > box.height(forWidth: 4_000) - 1)
    }

    @Test func aLongTextScrollsInsideABoxOfBoundedHeight() {
        let box = DetailBoxView()
        let long = (1...400).map { "line \($0) " + String(repeating: "wide ", count: 40) }.joined(separator: "\n")
        box.show([(long, nil)], palette: ChatPalette(appearance: .graphite))
        let height = box.height(forWidth: 500)
        #expect(height == DetailBoxView.maximumHeight + 2 * DetailBoxView.padding.height)
        box.frame = NSRect(x: 0, y: 0, width: 500, height: height)
        box.layoutSubtreeIfNeeded()
        // Every line is in the text, and a long line wraps, so nothing waits
        // beyond the right edge.
        #expect(box.textView.frame.height > 400 * 14)
        #expect(box.textView.frame.width <= box.scrollView.contentView.bounds.width)
        #expect(box.scrollView.documentView === box.textView)
    }

    @Test func theCopyControlCopiesTheWholeText() {
        let box = DetailBoxView()
        box.show([("swift test", nil)], palette: ChatPalette(appearance: .graphite))
        #expect(box.copyButton.isHidden)
        box.copyText = "all of the output"
        #expect(!box.copyButton.isHidden)
        box.pasteboard = NSPasteboard.withUniqueName()
        defer { box.pasteboard.releaseGlobally() }
        box.copyButton.performClick(nil)
        #expect(box.pasteboard.string(forType: .string) == "all of the output")
    }
}
