import AppKit
import Testing
@testable import MarkdownText

struct MarkdownLayoutManagerTests {
    @Test func theBoxOfInlineCodeHoldsTheLettersAndNotTheFullLine() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let line = NSRect(x: 40, y: 100, width: 60, height: 30)
        let box = MarkdownLayoutManager.inlineCodeBox(around: line, baseline: 24, font: font)
        #expect(box.height < line.height)
        #expect(box.minY >= line.minY)
        #expect(box.minY <= 124 - font.ascender)
        #expect(box.maxY >= 124 - font.descender)
        #expect(box.minX < line.minX && box.maxX > line.maxX)
    }
}
