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

    @Test func tablesReadTheirAlignmentsAndFitTheirRows() {
        let table = MarkdownTable(
            header: ["Name", "Size", "Note"], alignments: [.leading, .trailing, .center],
            rows: [["a", "1", ""], ["b `|` c", "2", "x"]])
        #expect(kinds("| Name | Size | Note |\n|---|--:|:-:|\n| a | 1 |\n| b `|` c | 2 | x | extra |\n\nText") == [
            .table(table), .paragraph("Text"),
        ])
        #expect(kinds("a | b\n--|--\n1 | 2") == [.table(MarkdownTable(header: ["a", "b"], alignments: [.leading, .leading], rows: [["1", "2"]]))])
        #expect(kinds("a | b\nno delimiter") == [.paragraph("a | b\nno delimiter")])
        #expect(kinds("Text\n| a |\n|---|") == [.paragraph("Text"), .table(MarkdownTable(header: ["a"], alignments: [.leading], rows: []))])
    }

    @Test func aTableThatStreamsShowsAsATableFromItsFirstRow() {
        var parser = MarkdownBlockParser(lines: ["| a | b |", "|--"], isComplete: false)
        parser.run()
        #expect(parser.blocks.map(\.kind) == [.table(MarkdownTable(header: ["a", "b"], alignments: [.leading, .leading], rows: []))])
    }

    @Test func listsNestAndKeepTheirMarkers() {
        let blocks = blocks("- one\n  - two\n    more\n1. first\n2) second\n- [ ] open\n- [x] done")
        #expect(blocks.map(\.kind) == [
            .listItem(.bullet, text: "one"), .listItem(.bullet, text: "two\nmore"), .listItem(.number(1), text: "first"),
            .listItem(.number(2), text: "second"), .listItem(.task(isDone: false), text: "open"),
            .listItem(.task(isDone: true), text: "done"),
        ])
        #expect(blocks.map(\.listDepth) == [1, 2, 1, 1, 1, 1])
        #expect(kinds("Text\n- item\nlazy\n\nafter") == [.paragraph("Text"), .listItem(.bullet, text: "item\nlazy"), .paragraph("after")])
    }

    @Test func aListItemHoldsCodeAndASecondParagraph() {
        let blocks = blocks("1. Run:\n\n   ```sh\n   swift build\n   ```\n\n   Then test.\n\nAfter")
        #expect(blocks.map(\.kind) == [
            .listItem(.number(1), text: "Run:"), .code(language: "sh", text: "swift build", isClosed: true),
            .paragraph("Then test."), .paragraph("After"),
        ])
        #expect(blocks.map(\.listDepth) == [1, 1, 1, 0])
    }

    @Test func aNestedListUnderANumberCanUseTwoSpaces() {
        #expect(blocks("1. Step\n  - detail\n2. Next").map(\.listDepth) == [1, 2, 1])
    }

    @Test func quotesHoldBlocksOneLevelDeeper() {
        let blocks = blocks("> Quoted\nlazy line\n> - item\n\nOut\n> again")
        #expect(blocks.map(\.kind) == [.paragraph("Quoted\nlazy line"), .listItem(.bullet, text: "item"), .paragraph("Out"), .paragraph("again")])
        #expect(blocks.map(\.quoteDepth) == [1, 1, 0, 1])
    }
}
