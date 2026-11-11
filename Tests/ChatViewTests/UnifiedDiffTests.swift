import Testing

@testable import ChatView

struct UnifiedDiffTests {
    @Test func aDiffCountsItsLinesAndDropsTheHeaders() {
        let diff = UnifiedDiff("--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n one\n-two\n+2\n+3\n\\ No newline at end of file")
        #expect(diff.lines.map(\.kind) == [.hunk, .context, .removed, .added, .added, .hunk])
        #expect(diff.lines.map(\.text) == ["@@ -1,3 +1,3 @@", "one", "two", "2", "3", "\\ No newline at end of file"])
        #expect(diff.countText == "+2 \u{2212}1")
    }

    @Test func anEmptyLineInAHunkIsNoLine() {
        #expect(UnifiedDiff("@@ -1 +1 @@\n-a\n+b\n").lines.count == 3)
    }
}
