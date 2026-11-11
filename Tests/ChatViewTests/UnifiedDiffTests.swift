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

    @Test func anEditBecomesADiffOfItsOldAndNewText() {
        let diff = UnifiedDiff(old: "keep\nold one\nold two\nend", new: "keep\nnew\nend", title: "Edit 1 of 2")
        #expect(diff.lines.map(\.kind) == [.hunk, .context, .removed, .removed, .added, .context])
        #expect(diff.lines.map(\.text) == ["Edit 1 of 2", "keep", "old one", "old two", "new", "end"])
        #expect(diff.countText == "+1 \u{2212}2")
    }

    @Test func diffsJoinInOrder() {
        var diff = UnifiedDiff(old: "a", new: "b", title: "Edit 1 of 2")
        diff.append(UnifiedDiff(old: "", new: "c", title: "Edit 2 of 2"))
        #expect(diff.lines.map(\.text) == ["Edit 1 of 2", "a", "b", "Edit 2 of 2", "c"])
        #expect(diff.countText == "+2 \u{2212}1")
    }
}
