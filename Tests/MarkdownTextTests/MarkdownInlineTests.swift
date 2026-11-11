import Testing
@testable import MarkdownText

struct MarkdownInlineTests {
    private func spans(_ text: String, streaming: Bool = false) -> [MarkdownSpan] {
        MarkdownInlineParser.spans(of: text, isStreaming: streaming)
    }

    @Test func plainTextIsOneSpanAndEscapesLoseTheirBackslash() {
        #expect(spans("Plain text\nwith a line") == [MarkdownSpan("Plain text\nwith a line")])
        #expect(spans(#"\*escaped\* \\ \a"#) == [MarkdownSpan(#"*escaped* \ \a"#)])
        #expect(spans("").isEmpty)
    }
}
