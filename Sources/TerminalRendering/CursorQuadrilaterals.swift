import TerminalEmulation

/// The quadrilaterals of the cursor. A block fills its cell and goes under the glyphs.
/// The other shapes are lines that go on top of them.
struct CursorQuadrilaterals {
    private(set) var backgrounds: [CellQuadrilateral] = []
    private(set) var overlays: [CellQuadrilateral] = []

    /// - Parameters:
    ///   - horizontalPosition: The left side of the cursor in pixels of the drawable.
    ///   - verticalPosition: The top of the cursor.
    ///   - width: One cell, or 2 cells on a wide character.
    ///   - stroke: The thickness of a line.
    init(style: CursorStyle, horizontalPosition: Int, verticalPosition: Int, width: Int, height: Int,
         stroke: Int, color: TerminalColor) {
        func rectangle(_ horizontalPosition: Int, _ verticalPosition: Int, _ width: Int, _ height: Int) -> CellQuadrilateral {
            .rectangle(horizontalPosition: horizontalPosition, verticalPosition: verticalPosition,
                       width: width, height: height, color: color)
        }
        switch style {
        case .block:
            backgrounds = [rectangle(horizontalPosition, verticalPosition, width, height)]
        case .bar:
            overlays = [rectangle(horizontalPosition, verticalPosition, 2 * stroke, height)]
        case .underline:
            overlays = [rectangle(horizontalPosition, verticalPosition + height - 2 * stroke, width, 2 * stroke)]
        case .hollowBlock:
            overlays = [
                rectangle(horizontalPosition, verticalPosition, width, stroke),
                rectangle(horizontalPosition, verticalPosition + height - stroke, width, stroke),
                rectangle(horizontalPosition, verticalPosition, stroke, height),
                rectangle(horizontalPosition + width - stroke, verticalPosition, stroke, height),
            ]
        }
    }
}
