import Testing

@testable import ChatView

struct BoundedLinesTests {
    @Test func longTextShowsOnlyItsFirstLines() {
        let output = (1...10_000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let lines = BoundedLines(output, lineLimit: 3)
        #expect(lines.text == "line 1\nline 2\nline 3")
        #expect(lines.hiddenLineCount == 9_997)
        #expect(BoundedLines("a\n\n\nb", lineLimit: 1).hiddenLineCount == 3)
        #expect(BoundedLines("a\nb", lineLimit: 2) == BoundedLines("a\nb\n", lineLimit: 5))
    }
}
