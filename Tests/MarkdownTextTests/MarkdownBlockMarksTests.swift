import AppKit
import Testing
@testable import MarkdownText

struct MarkdownBlockMarksTests {
    let marks = MarkdownBlockMarks(style: MarkdownTestStyle.standard, indentation: 22)

    @Test func eachListMarkEndsWithATab() {
        #expect(marks.mark(.bullet, depth: 1).string == "•\t")
        #expect(marks.mark(.bullet, depth: 2).string == "◦\t")
        #expect(marks.mark(.number(12), depth: 1).string == "12.\t")
        let task = marks.mark(.task(isDone: true), depth: 1)
        #expect(task.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
    }

    @Test func aQuoteBarMovesInWithItsDepth() {
        let block = marks.quoteBlock(depth: 2)
        #expect(block.width(for: .border, edge: .minX) == 3)
        #expect(block.width(for: .margin, edge: .minX) == 22)
    }

    @Test func aRuleIsALineUnderAnEmptyBlock() {
        let paragraph = marks.rule(spacingBefore: 10).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let block = paragraph?.textBlocks.first
        #expect(block?.width(for: .border, edge: .maxY) == 1)
        #expect(block?.width(for: .margin, edge: .minY) == 10)
    }
}
