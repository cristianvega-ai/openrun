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

    @Test func codeBlocksKeepTheirTextAndLanguage() {
        #expect(kinds("```swift\nlet a = 1\n\n  indented\n```\nafter") == [
            .code(language: "swift", text: "let a = 1\n\n  indented", isClosed: true), .paragraph("after"),
        ])
        #expect(kinds("~~~\n# not a heading\n````") == [.code(language: nil, text: "# not a heading\n````", isClosed: false)])
        #expect(kinds("````\n```\n````") == [.code(language: nil, text: "```", isClosed: true)])
        #expect(kinds("Text\n```\ncode\n```") == [.paragraph("Text"), .code(language: nil, text: "code", isClosed: true)])
    }
}
