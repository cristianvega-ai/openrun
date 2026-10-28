import TerminalEmulation

/// The lines that a cell can have: an underline in one of five styles, a line
/// through the text, and a line over it.
enum DecorationQuadrilaterals {
    /// The position is the left side of the cell. A program can give the underline its own color.
    static func lines(for cell: RenderCell, horizontalPosition: Int, color: TerminalColor, metrics: CellMetrics) -> [CellQuadrilateral] {
        let thickness = metrics.underlineThickness
        let underline = metrics.underlinePosition
        let underlineColor = cell.underlineColor ?? color
        func line(_ left: Int, _ top: Int, _ width: Int, _ color: TerminalColor) -> CellQuadrilateral {
            .rectangle(horizontalPosition: horizontalPosition + left, verticalPosition: top,
                       width: width, height: thickness, color: color)
        }
        var quads: [CellQuadrilateral] = []
        switch cell.style.underline {
        case .single:
            quads.append(line(0, underline, metrics.width, underlineColor))
        case .double:
            quads += [underline - thickness, underline + thickness].map { line(0, $0, metrics.width, underlineColor) }
        case .dotted:
            quads += stride(from: 0, to: metrics.width, by: 2 * thickness).map { line($0, underline, thickness, underlineColor) }
        case .dashed:
            // Each cell has one dash, so a row of cells shows a pattern of dashes.
            quads.append(line(0, underline, metrics.width * 3 / 5, underlineColor))
        case .curly, .none:
            break
        }
        if cell.style.isStruckThrough { quads.append(line(0, metrics.strikethroughPosition, metrics.width, color)) }
        if cell.style.isOverlined { quads.append(line(0, 0, metrics.width, color)) }
        return quads
    }
}

typealias DecorationQuads = DecorationQuadrilaterals
