import CoreGraphics
import CoreText
import Foundation

/// Draws a glyph with CoreText into a bitmap. CoreText shapes the cluster and
/// picks a fallback font for a character that SF Mono does not have.
struct GlyphRasterizer {
    /// A glyph in pixels, with its place relative to the cell.
    struct Bitmap {
        /// Row by row from the top: one byte for each pixel of a text glyph, or
        /// 4 bytes (blue, green, red, alpha) for the pixel of a color glyph.
        let pixels: [UInt8]
        let width: Int
        let height: Int
        /// From the top left of the cell to the top left of the bitmap.
        let offsetX: Int
        let offsetY: Int
        /// Whether the font gives its own colors, as for an emoji.
        let isColor: Bool
    }

    /// Empty pixels around the ink, so a filter never reads a neighbor.
    static let padding = 2
    let fonts: FontSet

    /// The bitmap of a glyph, or `nil` for one that draws nothing, such as a space.
    func bitmap(for key: GlyphKey) -> Bitmap? {
        if key == .curlyUnderline { return curlyUnderline() }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): fonts.font(for: key.face),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: key.text, attributes: attributes))
        let isColor = Self.usesColorFont(line)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let advance = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        // An emoji is a picture with no outline, so its box comes from the
        // metrics of its font. It shrinks to fit its cells and never grows.
        let space = CGFloat(key.columns * fonts.cellWidth)
        let baseline = CGFloat(fonts.metrics.baseline)
        let scale = isColor
            ? min(1, space / advance, baseline / ascent, (CGFloat(fonts.cellHeight) - baseline) / descent) : 1
        let ink = isColor
            ? CGRect(x: 0, y: -descent, width: advance, height: ascent + descent)
            : CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let box = ink.applying(CGAffineTransform(scaleX: scale, y: scale))
        guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
        // The origin of the line, from the bottom left of the bitmap.
        let originX = Self.padding - Int(box.minX.rounded(.down))
        let originY = Self.padding - Int(box.minY.rounded(.down))
        let width = Int(box.maxX.rounded(.up)) + originX + Self.padding
        let height = Int(box.maxY.rounded(.up)) + originY + Self.padding
        var pixels = [UInt8](repeating: 0, count: width * height * (isColor ? 4 : 1))
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = Self.context(for: buffer, width: width, height: height, isColor: isColor) else { return false }
            context.translateBy(x: CGFloat(originX), y: CGFloat(originY))
            context.scaleBy(x: scale, y: scale)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }
        // A glyph that is narrower than its cells sits in their middle.
        let center = advance * scale < space ? Int(((space - advance * scale) / 2).rounded()) : 0
        return Bitmap(
            pixels: pixels, width: width, height: height, offsetX: center - originX,
            offsetY: Int(baseline) - (height - originY), isColor: isColor)
    }

    /// A wave as wide as one cell. It starts and ends in its middle, so the
    /// waves of two cells next to each other join.
    private func curlyUnderline() -> Bitmap? {
        let metrics = fonts.metrics
        let thickness = CGFloat(metrics.underlineThickness)
        let (width, height) = (metrics.width, metrics.underlineThickness * 4 + 2)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = Self.context(for: buffer, width: width, height: height, isColor: false) else { return false }
            let middle = CGFloat(height) / 2
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setLineWidth(thickness)
            context.move(to: CGPoint(x: 0, y: middle))
            for step in 1...width * 4 {
                let x = CGFloat(step) / 4
                context.addLine(to: CGPoint(x: x, y: middle + (middle - thickness) * sin(x / CGFloat(width) * 2 * .pi)))
            }
            context.strokePath()
            return true
        }
        let top = metrics.underlinePosition + metrics.underlineThickness / 2 - height / 2
        return drawn ? Bitmap(pixels: pixels, width: width, height: height, offsetX: 0, offsetY: top, isColor: false) : nil
    }

    /// The number of cells that a cluster covers: 2 for a character that is
    /// about as wide as 2 cells, such as a Japanese character, and 1 otherwise.
    func columns(of text: String) -> Int {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): fonts.font(for: .regular)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CTLineGetTypographicBounds(line, nil, nil, nil) / CGFloat(fonts.cellWidth) > 1.5 ? 2 : 1
    }

    private static func usesColorFont(_ line: CTLine) -> Bool {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.contains { run in
            guard let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { return false }
            return CTFontGetSymbolicTraits(font as! CTFont).contains(.traitColorGlyphs)
        }
    }

    private static func context(for buffer: UnsafeMutableRawBufferPointer, width: Int, height: Int, isColor: Bool) -> CGContext? {
        let context = isColor
            ? CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            : CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        context?.setFillColor(gray: 1, alpha: 1)
        // Whole pixels keep every glyph sharp and the same each time.
        context?.setShouldSubpixelPositionFonts(false)
        context?.setShouldSubpixelQuantizeFonts(false)
        return context
    }
}
