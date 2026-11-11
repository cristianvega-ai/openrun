import Testing
@testable import MarkdownText

struct MarkdownBlockTests {
    private func blocks(_ text: String) -> [MarkdownBlock] {
        var parser = MarkdownBlockParser(lines: text.split(separator: "\n", omittingEmptySubsequences: false), isComplete: true)
        parser.run()
        return parser.blocks
    }

    private func kinds(_ text: String) -> [MarkdownBlockKind] {
        blocks(text).map(\.kind)
    }

    @Test func headingsParagraphsAndRules() {
        #expect(kinds("# One\n\nText on\ntwo lines\n\n---\n### Three ###") == [
            .heading(level: 1, text: "One"), .paragraph("Text on\ntwo lines"), .rule, .heading(level: 3, text: "Three"),
        ])
        #expect(kinds("#hashtag") == [.paragraph("#hashtag")])
        #expect(kinds("####### seven") == [.paragraph("####### seven")])
    }

    @Test func aBlockStartEndsAParagraph() {
        #expect(kinds("Text\n# Head\nMore\n***") == [.paragraph("Text"), .heading(level: 1, text: "Head"), .paragraph("More"), .rule])
    }
}
