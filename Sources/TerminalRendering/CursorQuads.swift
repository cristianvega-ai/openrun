import TerminalEmulation

/// The quads of the cursor. A block fills its cell and goes under the glyphs.
/// The other shapes are lines that go on top of them.
struct CursorQuads {
    private(set) var backgrounds: [CellQuad] = []
    private(set) var overlays: [CellQuad] = []

    /// - Parameters:
    ///   - x: The left side of the cursor in pixels of the drawable.
    ///   - y: The top of the cursor.
    ///   - width: One cell, or 2 cells on a wide character.
    ///   - stroke: The thickness of a line.
    init(style: CursorStyle, x: Int, y: Int, width: Int, height: Int, stroke: Int, color: TerminalColor) {
        func rectangle(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CellQuad {
            .rectangle(x: x, y: y, width: width, height: height, color: color)
        }
        switch style {
        case .block:
            backgrounds = [rectangle(x, y, width, height)]
        case .bar:
            overlays = [rectangle(x, y, 2 * stroke, height)]
        case .underline:
            overlays = [rectangle(x, y + height - 2 * stroke, width, 2 * stroke)]
        case .hollowBlock:
            overlays = [
                rectangle(x, y, width, stroke), rectangle(x, y + height - stroke, width, stroke),
                rectangle(x, y, stroke, height), rectangle(x + width - stroke, y, stroke, height),
            ]
        }
    }
}
