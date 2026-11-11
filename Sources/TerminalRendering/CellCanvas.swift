import CoreGraphics

/// A bitmap of coverage with the exact size of a cell, for a character that the
/// renderer draws in code. A font draws a box character with its own side
/// bearings and height, so the frames of agents show gaps between the cells.
/// A canvas fills the cell to its edges, and two neighbors meet with no gap.
/// Positions count in pixels from the top left of the cell.
struct CellCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int) {
        (self.width, self.height) = (max(1, width), max(1, height))
        pixels = [UInt8](repeating: 0, count: self.width * self.height)
    }

    /// The thickness of a light line. It follows the width of the cell, so the
    /// lines grow with the text, and it is a whole number of pixels, so they stay sharp.
    var lightThickness: Int { max(1, Int((Double(width) / 8).rounded())) }

    /// Fills the whole pixels from `left` to `right` and from `top` to `bottom`,
    /// with the right and bottom ends excluded. A part outside the cell is cut off.
    mutating func fill(left: Int, top: Int, right: Int, bottom: Int, coverage: UInt8 = 255) {
        let (left, right, top, bottom) = (max(0, left), min(width, right), max(0, top), min(height, bottom))
        guard left < right, top < bottom else { return }
        for row in top..<bottom {
            for column in left..<right {
                let index = row * width + column
                pixels[index] = max(pixels[index], coverage)
            }
        }
    }

    /// The coverage of one pixel, or zero outside the cell.
    func coverage(column: Int, row: Int) -> UInt8 {
        guard (0..<width).contains(column), (0..<height).contains(row) else { return 0 }
        return pixels[row * width + column]
    }

    /// Draws curves, diagonals and triangles with smooth edges. The context
    /// counts from the top left, as the cell does, and its color is full coverage.
    mutating func draw(_ body: (CGContext) -> Void) {
        let (width, height) = (width, height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(gray: 1, alpha: 1)
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setLineCap(.butt)
            body(context)
        }
    }

    /// The canvas as a glyph that covers its cells from the top left corner.
    var bitmap: GlyphRasterizer.Bitmap {
        GlyphRasterizer.Bitmap(pixels: pixels, width: width, height: height, horizontalOffset: 0, verticalOffset: 0, isColor: false)
    }
}
