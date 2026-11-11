import AppKit
import Testing
@testable import MarkdownText

struct MarkdownRendererTests {
    let renderer = MarkdownRenderer(style: MarkdownTestStyle.standard)

    private func paragraph(_ text: NSAttributedString) -> NSParagraphStyle? {
        text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func blocksGetTheirTextAndSpacing() {
        let blocks = MarkdownDocument(text: "# Title\n\nText\n\n- one\n- two\n\n## Next").blocks
        let texts = blocks.indices.map { renderer.attributedString(for: blocks[$0], after: $0 > 0 ? blocks[$0 - 1] : nil) }
        #expect(texts.map(\.string) == ["Title", "Text", "•\tone", "•\ttwo", "Next"])
        #expect(texts.map { paragraph($0)?.paragraphSpacingBefore } == [0, 6, 11, 4, 20])
        #expect((texts[0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20)
    }

    @Test func listItemsIndentByTheirDepth() {
        let blocks = MarkdownDocument(text: "- one\n  - two\n\n    more").blocks
        let styles = blocks.map { paragraph(renderer.attributedString(for: $0, after: nil)) }
        #expect(styles.map { $0?.headIndent } == [22, 44, 44])
        #expect(styles.map { $0?.firstLineHeadIndent } == [0, 22, 44])
        #expect(styles[1]?.tabStops.map(\.location) == [44])
    }

    @Test func quotedTextIsQuietWithABar() {
        let block = MarkdownDocument(text: "> quoted").blocks[0]
        let text = renderer.attributedString(for: block, after: nil)
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == renderer.style.secondaryTextColor)
        #expect(paragraph(text)?.textBlocks.count == 1)
    }

    @Test func codeKeepsItsTextWithoutAWrap() {
        let block = MarkdownDocument(text: "```\nlet a = 1\n```").blocks[0]
        let text = renderer.attributedString(for: block, after: nil)
        #expect(text.string == "let a = 1")
        #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.isFixedPitch == true)
        #expect(paragraph(text)?.lineBreakMode == .byClipping)
    }

    @Test func theSeparatorTakesTheStyleOfTheBlockBeforeIt() {
        let block = MarkdownDocument(text: "> [link](https://example.com)").blocks[0]
        let text = renderer.attributedString(for: block, after: nil)
        let separator = MarkdownRenderer.separator(after: text)
        #expect(separator.string == "\n")
        #expect(paragraph(separator) == paragraph(text))
        #expect(separator.attribute(.link, at: 0, effectiveRange: nil) == nil)
    }
}
