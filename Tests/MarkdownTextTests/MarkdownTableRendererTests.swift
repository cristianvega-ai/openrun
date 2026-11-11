import AppKit
import Testing
@testable import MarkdownText

struct MarkdownTableRendererTests {
    let style = MarkdownTestStyle.standard

    @Test func eachCellIsAParagraphOfTheTable() throws {
        let table = MarkdownTable(header: ["Name", "Size"], alignments: [.leading, .trailing], rows: [["a", ""]])
        let text = MarkdownTableRenderer(style: style, isStreaming: false).attributedString(table, spacingBefore: 8)
        #expect(text.string == "Name\nSize\na\n\u{200B}")
        var blocks: [NSTextTableBlock] = []
        var alignments: [NSTextAlignment] = []
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let paragraph = value as? NSParagraphStyle, let block = paragraph.textBlocks.first as? NSTextTableBlock else { return }
            blocks.append(block)
            alignments.append(paragraph.alignment)
        }
        #expect(blocks.map(\.startingRow) == [0, 0, 1, 1])
        #expect(blocks.map(\.startingColumn) == [0, 1, 0, 1])
        #expect(alignments == [.natural, .right, .natural, .right])
        #expect(blocks[0].backgroundColor == style.tableHeaderBackgroundColor)
        #expect(blocks[2].backgroundColor == nil)
        #expect(blocks[0].table.numberOfColumns == 2)
        #expect(blocks[0].table.width(for: .margin, edge: .minY) == 8)
        let header = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(header.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
