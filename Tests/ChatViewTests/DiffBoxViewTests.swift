import AppKit
import Testing

@testable import ChatView

@MainActor struct DiffBoxViewTests {
    @Test func aLongDiffShowsEveryLineInABoxThatScrolls() {
        let text = "@@ -1,1000 +1,1000 @@\n" + (1...1_000).map { "+line \($0)" }.joined(separator: "\n")
        let box = DiffBoxView()
        box.show(UnifiedDiff(text), palette: ChatPalette(appearance: .graphite))
        let height = box.height(forWidth: 600)
        #expect(height == DiffBoxView.maximumHeight + 2 * DiffBoxView.padding)
        box.frame = NSRect(x: 0, y: 0, width: 600, height: height)
        box.layoutSubtreeIfNeeded()
        #expect(box.linesView.frame.height == 1_001 * box.linesView.lineHeight)
        #expect(box.scrollView is InnerScrollView)
    }
}
