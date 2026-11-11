import Testing

@testable import ChatView

@MainActor struct DetailBoxViewTests {
    @Test func theBoxShowsEachPartAndItsNote() {
        let box = DetailBoxView()
        box.show([("swift test", nil), ("line 1\nline 2", "3 more lines")], palette: ChatPalette(appearance: .graphite))
        #expect(box.textView.string == "swift test\nline 1\nline 2\n3 more lines")
        #expect(box.height(forWidth: 400) > box.height(forWidth: 4_000) - 1)
    }
}
