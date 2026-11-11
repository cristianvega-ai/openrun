import Testing

@testable import ChatView

struct DroppedPathTests {
    @Test func aPlainPathStaysAsItIs() {
        #expect(DroppedPath.text(of: "/work/app/Sources/main.swift") == "/work/app/Sources/main.swift")
    }

    @Test func aPathWithASpaceOrAQuoteStaysOnePath() {
        #expect(DroppedPath.text(of: "/work/My Notes/a.txt") == "'/work/My Notes/a.txt'")
        #expect(DroppedPath.text(of: "/work/it's.txt") == "'/work/it'\\''s.txt'")
    }

    @Test func aLineBreakOrAControlCharacterShowsAsAnEscape() {
        #expect(DroppedPath.text(of: "/work/a\nb.txt") == "$'/work/a\\nb.txt'")
        #expect(DroppedPath.text(of: "/work/a\u{1B}'b") == "$'/work/a\\x1b\\'b'")
    }
}
