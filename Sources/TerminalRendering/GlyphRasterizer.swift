import CoreGraphics
import CoreText
import Foundation

/// Draws a glyph with CoreText into a bitmap. CoreText shapes the cluster and
/// picks a fallback font for a character that SF Mono does not have.
struct GlyphRasterizer {
    /// A glyph in pixels, with its place relative to the cell.
    struct Bitmap {
        /// One byte for each pixel, row by row from the top.
        let pixels: [UInt8]
        let width: Int
        let height: Int
        /// From the top left of the cell to the top left of the bitmap.
        let offsetX: Int
        let offsetY: Int
    }

    /// Empty pixels around the ink, so a filter never reads a neighbor.
    static let padding = 2
    let fonts: FontSet

    /// The bitmap of a glyph, or `nil` for one that draws nothing, such as a space.
    func bitmap(for key: GlyphKey) -> Bitmap? {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): fonts.font(for: key.face),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: key.text, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard !ink.isNull, ink.width > 0, ink.height > 0 else { return nil }
        // The origin of the line, from the bottom left of the bitmap.
        let originX = Self.padding - Int(ink.minX.rounded(.down))
        let originY = Self.padding - Int(ink.minY.rounded(.down))
        let width = Int(ink.maxX.rounded(.up)) + originX + Self.padding
        let height = Int(ink.maxY.rounded(.up)) + originY + Self.padding
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            // Whole pixels keep every glyph sharp and the same each time.
            context.setShouldSubpixelPositionFonts(false)
            context.setShouldSubpixelQuantizeFonts(false)
            context.textPosition = CGPoint(x: originX, y: originY)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }
        // A glyph that is narrower than its cells sits in their middle.
        let space = CGFloat(key.columns * fonts.cellWidth)
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let center = advance < space ? Int(((space - advance) / 2).rounded()) : 0
        return Bitmap(
            pixels: pixels, width: width, height: height,
            offsetX: center - originX, offsetY: fonts.metrics.baseline - (height - originY))
    }
}
