import AppKit

/// A layout manager that draws the background of inline code as a small
/// rounded box around the letters.
///
/// TextKit fills a background over the full height of the line, which
/// with the extra height of prose lines makes inline code look like a
/// tall bar that touches the line above.
public final class MarkdownLayoutManager: NSLayoutManager {
    public override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor
    ) {
        guard let storage = textStorage, charRange.location < storage.length,
              storage.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? NSColor == color,
              let font = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont
        else {
            return super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
        let glyph = glyphIndexForCharacter(at: charRange.location)
        let baseline = location(forGlyphAt: glyph).y
        color.setFill()
        for rect in UnsafeBufferPointer(start: rectArray, count: rectCount) {
            let box = Self.inlineCodeBox(around: rect, baseline: baseline, font: font)
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        }
    }

    /// The box of inline code in a background rectangle of the full line.
    /// - Parameter baseline: The baseline from the top of the line.
    static func inlineCodeBox(around rect: NSRect, baseline: CGFloat, font: NSFont) -> NSRect {
        let top = rect.minY + baseline - font.ascender - 2
        let height = min(rect.height, font.ascender - font.descender + 4)
        return NSRect(x: rect.minX - 2, y: max(rect.minY, top), width: rect.width + 4, height: height)
    }
}
