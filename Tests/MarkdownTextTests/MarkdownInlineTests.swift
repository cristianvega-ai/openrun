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

    @Test func codeSpansKeepTheirMarksAndLoseOneSpace() {
        #expect(spans("`` a ` b `` and `**x**`") == [
            MarkdownSpan("a ` b", style: .code), MarkdownSpan(" and "), MarkdownSpan("**x**", style: .code),
        ])
        #expect(spans("`not closed") == [MarkdownSpan("`not closed")])
        #expect(spans("run `swift bu", streaming: true) == [MarkdownSpan("run "), MarkdownSpan("swift bu", style: .code)])
    }

    @Test func emphasisAndStrikethrough() {
        #expect(spans("a **b** *c* ***d*** __e__ ~~f~~") == [
            MarkdownSpan("a "), MarkdownSpan("b", style: .bold), MarkdownSpan(" "), MarkdownSpan("c", style: .italic),
            MarkdownSpan(" "), MarkdownSpan("d", style: [.bold, .italic]), MarkdownSpan(" "), MarkdownSpan("e", style: .bold),
            MarkdownSpan(" "), MarkdownSpan("f", style: .strikethrough),
        ])
        #expect(spans("**bold *both***") == [MarkdownSpan("bold ", style: .bold), MarkdownSpan("both", style: [.bold, .italic])])
        #expect(spans("*a `*` b*") == [MarkdownSpan("a ", style: .italic), MarkdownSpan("*", style: [.italic, .code]), MarkdownSpan(" b", style: .italic)])
    }

    @Test func marksThatOpenNothingStay() {
        #expect(spans("2 * 3 = 6, snake_case_name, ~one~, a ** b") == [MarkdownSpan("2 * 3 = 6, snake_case_name, ~one~, a ** b")])
        #expect(spans("**not closed") == [MarkdownSpan("**not closed")])
    }

    @Test func emphasisThatHasNotClosedAtTheEndOfAStreamShowsAsClosed() {
        #expect(spans("a **bo", streaming: true) == [MarkdownSpan("a "), MarkdownSpan("bo", style: .bold)])
        #expect(spans("**a** b", streaming: true) == [MarkdownSpan("a", style: .bold), MarkdownSpan(" b")])
        #expect(spans("a *", streaming: true) == [MarkdownSpan("a *")])
    }

    @Test func linksAreDataWithTheirText() {
        #expect(spans("see [the **docs**](https://example.com/a_(b) \"Title\") now") == [
            MarkdownSpan("see "), MarkdownSpan("the ", link: "https://example.com/a_(b)"),
            MarkdownSpan("docs", style: .bold, link: "https://example.com/a_(b)"), MarkdownSpan(" now"),
        ])
        #expect(spans("![a picture](image.png) [b](<c d>)") == [MarkdownSpan("a picture", link: "image.png"), MarkdownSpan(" "), MarkdownSpan("b", link: "c d")])
        #expect(spans("[1] and [a](b and") == [MarkdownSpan("[1] and [a](b and")])
    }

    @Test func aLinkThatHasNotClosedAtTheEndOfAStreamShowsAsALink() {
        #expect(spans("see [the do", streaming: true) == [MarkdownSpan("see "), MarkdownSpan("the do", link: "")])
        #expect(spans("see [the docs](https://exa", streaming: true) == [MarkdownSpan("see "), MarkdownSpan("the docs", link: "")])
        #expect(spans("array[0", streaming: true) == [MarkdownSpan("array[0")])
    }
}
