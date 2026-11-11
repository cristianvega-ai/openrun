/// The characters that the renderer draws in code in place of the font
/// (decision of 2026-10-27). Each one fills its cells to the edges, so the
/// frames and bars that programs draw with them have no gaps.
enum DrawnGlyph {
    /// The bitmap of a key that holds one such character, or `nil` for any
    /// other text, which the font draws. The face does not change the drawing.
    static func bitmap(for key: GlyphKey, cellWidth: Int, cellHeight: Int) -> GlyphRasterizer.Bitmap? {
        let scalars = key.text.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        var canvas = CellCanvas(width: cellWidth * key.columns, height: cellHeight)
        if let arms = BoxLineArms(scalar) {
            arms.draw(on: &canvas)
        } else if !BoxDrawingShapes.draw(scalar, on: &canvas) {
            return nil
        }
        return canvas.bitmap
    }
}
