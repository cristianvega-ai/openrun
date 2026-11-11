import AppKit
import Testing
@testable import MarkdownText

struct MarkdownInlineRendererTests {
    let style = MarkdownTestStyle.standard

    private func render(_ text: String, streaming: Bool = false) -> NSAttributedString {
        MarkdownInlineRenderer.attributedString(text, isStreaming: streaming, font: style.bodyFont, color: style.textColor, style: style)
    }

    @Test func spansGetTheirFontsAndMarks() {
        let text = render("a **b** `c` ~~d~~")
        #expect(text.string == "a b c d")
        let bold = text.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect((text.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.isFixedPitch == true)
        #expect(text.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? NSColor == style.inlineCodeBackgroundColor)
        #expect(text.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func aLinkKeepsItsTargetAsDataAndShowsIt() {
        let text = render("see [docs](https://example.com/a)")
        #expect(text.string == "see docs")
        #expect(text.attribute(.link, at: 5, effectiveRange: nil) as? String == "https://example.com/a")
        #expect(text.attribute(.toolTip, at: 5, effectiveRange: nil) as? String == "https://example.com/a")
        #expect(text.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor == style.linkColor)
        let coming = render("see [do", streaming: true)
        #expect(coming.attribute(.link, at: 5, effectiveRange: nil) == nil)
        #expect(coming.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor == style.linkColor)
    }

    @Test func aLineBreakStaysInsideTheParagraph() {
        #expect(render("one\ntwo").string == "one\u{2028}two")
    }
}
