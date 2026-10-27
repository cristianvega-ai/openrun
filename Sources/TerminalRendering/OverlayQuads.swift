import TerminalEmulation

/// Quads that cover the whole picture, over the text and the cursor.
enum OverlayQuads {
    /// The flash of the visual bell: one rectangle of the text color. It is translucent, so the
    /// text under it stays readable.
    static func flash(width: Int, height: Int, color: TerminalColor) -> CellQuad {
        var quad = CellQuad.rectangle(x: 0, y: 0, width: width, height: height, color: color)
        quad.color.w = 0.3
        return quad
    }
}
