import Testing

@testable import ChatView

@MainActor struct DiffLinesViewTests {
    @Test func theViewIsAsTallAsItsLinesAndAsWideAsTheLongest() {
        let view = DiffLinesView()
        let diff = UnifiedDiff("@@ -1 +1 @@\n-short\n+" + String(repeating: "long ", count: 40))
        view.show(diff.lines, note: "1 more line", palette: ChatPalette(appearance: .graphite))
        #expect(abs(view.contentHeight - 4 * view.lineHeight) < 0.01)
        #expect(view.contentWidth > 400)
    }
}
